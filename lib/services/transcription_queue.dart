import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/queued_recording.dart';
import 'groq_service.dart';

class TranscriptionQueue {
  static final TranscriptionQueue instance = TranscriptionQueue._internal();

  static const int maxQueueSize = 20;
  static const int maxAttempts = 5;

  late Box<QueuedRecording> _box;
  Timer? _timer;
  bool _initialized = false;
  bool _isProcessing = false;

  TranscriptionQueue._internal();

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(QueuedRecordingAdapter().typeId)) {
      Hive.registerAdapter(QueuedRecordingAdapter());
    }
    _box = await Hive.openBox<QueuedRecording>('transcriptionQueue');
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      processQueue();
    });
    _initialized = true;
    unawaited(processQueue());
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> addRecording(File file, Duration duration, String uid) async {
    await init();
    if (_box.length >= maxQueueSize) {
      await _box.delete(_box.keys.first);
    }

    final rec = QueuedRecording()
      ..filePath = file.path
      ..durationSeconds = duration.inSeconds
      ..uid = uid
      ..timestamp = DateTime.now().millisecondsSinceEpoch
      ..status = 'pending'
      ..attempts = 0;
    await _box.add(rec);
    unawaited(processQueue());
  }

  Future<void> processQueue() async {
    if (!_initialized || _isProcessing) return;
    _isProcessing = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return;

      for (final key in _box.keys) {
        final rec = _box.get(key);
        if (rec == null || rec.status != 'pending') continue;

        if (rec.attempts >= maxAttempts) {
          rec.status = 'failed';
          await rec.save();
          continue;
        }

        try {
          final localFile = File(rec.filePath);
          if (!await localFile.exists()) {
            rec.status = 'failed';
            await rec.save();
            continue;
          }

          final storageRef = FirebaseStorage.instance
              .ref()
              .child('recordings')
              .child(rec.uid)
              .child('${rec.timestamp}.m4a');
          final uploadTask = storageRef.putFile(
            localFile,
            SettableMetadata(contentType: 'audio/m4a'),
          );
          final snapshot = await uploadTask.whenComplete(() {});
          final downloadUrl = await snapshot.ref.getDownloadURL();

          final transcription = await GroqService.transcribeAudio(downloadUrl);
          await FirebaseFirestore.instance.collection('notes').add({
            'userId': rec.uid,
            'title': 'Audio Note ${DateTime.fromMillisecondsSinceEpoch(rec.timestamp)}',
            'content': transcription,
            'audioUrl': downloadUrl,
            'recordingDurationSeconds': rec.durationSeconds,
            'timestamp': FieldValue.serverTimestamp(),
          });

          rec.status = 'completed';
          await rec.save();
          await localFile.delete();
        } catch (_) {
          rec.attempts += 1;
          await rec.save();
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}
