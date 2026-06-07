import 'dart:io';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Downloads and caches the Sherpa-ONNX KWS model (one-time, ~6 MB int8 pack).
class SherpaKwsModelManager {
  SherpaKwsModelManager._();
  static final SherpaKwsModelManager instance = SherpaKwsModelManager._();

  static const _modelFolder = 'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20';
  static const _archiveUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2';

  bool _preparing = false;

  Future<String?> ensureModelDir({void Function(String)? onStatus}) async {
    final root = await getApplicationDocumentsDirectory();
    final modelDir = p.join(root.path, _modelFolder);
    final encoder = p.join(
      modelDir,
      'encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
    );
    if (await File(encoder).exists()) {
      await _ensureKeywordsFile(modelDir);
      return modelDir;
    }

    if (_preparing) {
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (await File(encoder).exists()) {
          await _ensureKeywordsFile(modelDir);
          return modelDir;
        }
      }
      return null;
    }

    _preparing = true;
    try {
      onStatus?.call('Checking network for voice model…');
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        debugPrint('SherpaKwsModelManager: no network for first-time download');
        return null;
      }

      onStatus?.call('Downloading voice model (one time, ~6 MB)…');
      final response = await http.get(Uri.parse(_archiveUrl));
      if (response.statusCode != 200) {
        debugPrint('SherpaKwsModelManager: download failed ${response.statusCode}');
        return null;
      }

      final archive = BZip2Decoder().decodeBytes(response.bodyBytes);
      final tar = TarDecoder().decodeBytes(archive);
      for (final file in tar.files) {
        if (!file.isFile) continue;
        var name = file.name;
        if (name.startsWith('$_modelFolder/')) {
          name = name.substring(_modelFolder.length + 1);
        }
        if (name.isEmpty || name.contains('..')) continue;
        final out = File(p.join(modelDir, name));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
      }

      if (!await File(encoder).exists()) {
        debugPrint('SherpaKwsModelManager: encoder missing after extract');
        return null;
      }

      await _ensureKeywordsFile(modelDir);
      onStatus?.call('Voice model ready');
      return modelDir;
    } catch (e) {
      debugPrint('SherpaKwsModelManager: $e');
      return null;
    } finally {
      _preparing = false;
    }
  }

  Future<void> _ensureKeywordsFile(String modelDir) async {
    final dest = p.join(modelDir, 'keywords.txt');
    if (await File(dest).exists()) return;
    final bundled = await rootBundle.loadString('assets/sherpa/keywords.txt');
    await File(dest).writeAsString(bundled);
  }

  Future<sherpa.KeywordSpotter?> createSpotter(String modelDir) async {
    final encoder = p.join(
      modelDir,
      'encoder-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
    );
    final decoder = p.join(
      modelDir,
      'decoder-epoch-13-avg-2-chunk-8-left-64.onnx',
    );
    final joiner = p.join(
      modelDir,
      'joiner-epoch-13-avg-2-chunk-8-left-64.int8.onnx',
    );
    final tokens = p.join(modelDir, 'tokens.txt');
    final keywords = p.join(modelDir, 'keywords.txt');

    final model = sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
      ),
      tokens: tokens,
      numThreads: 2,
      debug: false,
      modelType: 'zipformer2',
    );

    final config = sherpa.KeywordSpotterConfig(
      model: model,
      keywordsFile: keywords,
      keywordsScore: 1.4,
      keywordsThreshold: 0.20,
      maxActivePaths: 4,
      numTrailingBlanks: 1,
    );

    return sherpa.KeywordSpotter(config);
  }
}
