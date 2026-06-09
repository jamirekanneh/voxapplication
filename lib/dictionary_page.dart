import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'language_provider.dart';
import 'analytics_service.dart';
import 'theme_provider.dart';
import 'services/mic_coordinator.dart';
import 'services/app_speech_service.dart';
import 'services/dictionary_search_history_service.dart';

// Wiktionary-backed language codes (freedictionaryapi.com).
const Map<String, String> _apiLangCode = {
  'English': 'en',
  'Spanish': 'es',
  'French': 'fr',
  'Arabic': 'ar',
  'Turkish': 'tr',
  'Chinese': 'zh',
};

String _normalizeSearchWord(String input, String langCode) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  const lowerLangs = {'en', 'es', 'fr', 'tr'};
  if (lowerLangs.contains(langCode)) return trimmed.toLowerCase();
  return trimmed;
}

// Merriam-Webster keys — register each reference at dictionaryapi.com.
const String _mwMedicalKey = '28965174-d50d-4d58-82fa-0ce787de8209';
const String _mwCollegiateKey = 'd315ee28-5f96-4830-b598-c387d1354bf1';
const String _mwLegalKey = ''; // Register Legal at dictionaryapi.com, then paste key here

enum _ResultSource { general, medical, legal, cs }

extension _SourceInfo on _ResultSource {
  String labelKey() {
    switch (this) {
      case _ResultSource.general:
        return 'dictionary_source_general';
      case _ResultSource.medical:
        return 'dictionary_source_medical';
      case _ResultSource.legal:
        return 'dictionary_source_legal';
      case _ResultSource.cs:
        return 'dictionary_source_technical';
    }
  }

  IconData get icon {
    switch (this) {
      case _ResultSource.general:
        return Icons.public_rounded;
      case _ResultSource.medical:
        return Icons.medical_services_outlined;
      case _ResultSource.legal:
        return Icons.gavel_rounded;
      case _ResultSource.cs:
        return Icons.computer_rounded;
    }
  }

}

_ResultSource? _resultSourceFromKey(String? key) {
  switch (key) {
    case 'general':
      return _ResultSource.general;
    case 'medical':
      return _ResultSource.medical;
    case 'legal':
      return _ResultSource.legal;
    case 'cs':
      return _ResultSource.cs;
    default:
      return null;
  }
}

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  static const _searchOwner = 'dictionary_search';

  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _focusNode = FocusNode();

  Map<String, dynamic>? _result;
  final Set<_ResultSource> _activeSources = {};
  List<DictionarySearchEntry> _recentSearches = [];
  String? _error;
  bool _loading = false;
  bool _isPlaying = false;
  bool _isListening = false;
  bool _searchMicHandoff = false;
  String? _audioUrl;
  bool _consumedRouteQuery = false;

  Future<void> _releaseDictionaryMic() async {
    if (_searchMicHandoff) return;
    await AppSpeechService.instance.stop();
    if (mounted) setState(() => _isListening = false);
    MicCoordinator.instance.setSearchMicActive(false);
  }

  @override
  void initState() {
    super.initState();
    MicCoordinator.instance.registerReleaseHandler(_releaseDictionaryMic);
    unawaited(_loadRecentSearches());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MicCoordinator.instance.syncRouteIfCurrent(context, '/dictionary');
    });
  }

  Future<void> _loadRecentSearches() async {
    final recent = await DictionarySearchHistoryService.instance.loadRecent();
    if (!mounted) return;
    setState(() => _recentSearches = recent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_consumedRouteQuery) return;
    _consumedRouteQuery = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final query = (args?['searchQuery'] as String?)?.trim() ?? '';
    if (query.isEmpty) return;

    _searchController.text = query;
    final lang = context.read<LanguageProvider>();
    final langCode = _apiLangCode[lang.selectedLanguage] ?? 'en';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search(langCode);
    });
  }

  @override
  void dispose() {
    MicCoordinator.instance.unregisterReleaseHandler(_releaseDictionaryMic);
    MicCoordinator.instance.setSearchMicActive(false);
    _searchController.dispose();
    _audioPlayer.dispose();
    _focusNode.dispose();
    if (AppSpeechService.instance.activeOwner == _searchOwner) {
      AppSpeechService.instance.stop();
    }
    super.dispose();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  VOICE SEARCH
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _startVoiceSearch(String langCode) async {
    if (_isListening) {
      await _releaseDictionaryMic();
      final word = _normalizeSearchWord(_searchController.text, langCode);
      if (word.isNotEmpty) _search(langCode);
      return;
    }

    await MicCoordinator.instance.yieldFromAssistant();

    if (!MicCoordinator.instance.searchMicMayListen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LanguageProvider>().t('chatbot_mic_menu_faqs'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (micStatus != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission denied'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final available = await AppSpeechService.instance.ensureInitialized(
      owner: _searchOwner,
      onError: (e) {
        if (_searchMicHandoff) return;
        MicCoordinator.instance.setSearchMicActive(false);
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (s) {
        if (_searchMicHandoff) return;
        if (s == 'done' || s == 'notListening') {
          MicCoordinator.instance.setSearchMicActive(false);
          if (mounted) {
            setState(() => _isListening = false);
            final word = _searchController.text.trim();
            if (word.isNotEmpty) _search(langCode);
          }
        }
      },
    );

    if (!mounted) return;

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Speech recognition not available on this device'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _searchMicHandoff = true;
    try {
      await MicCoordinator.instance.prepareForSearchMic(_releaseDictionaryMic);
      if (!mounted) return;

      setState(() {
        _isListening = true;
        _searchController.clear();
      });

      final langProvider = context.read<LanguageProvider>();
      await AppSpeechService.instance.listen(
        owner: _searchOwner,
        localeId: langProvider.sttLocale,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.search,
        ),
        onResult: (val) {
          final text = val.recognizedWords.trim();
          if (!mounted) return;
          setState(() => _searchController.text = text);
          if (val.finalResult && text.isNotEmpty) {
            _search(langCode);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );
    } finally {
      _searchMicHandoff = false;
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  MAIN SEARCH â€” smart routing
  //
  //  Strategy:
  //  1. Fire general + medical requests in parallel
  //  2. If general returns good definitions â†’ use it
  //  3. If general returns nothing / weak â†’ prefer medical if it found it
  //  4. If both fail â†’ show error with suggestions
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _search(String langCode) async {
    final word = _normalizeSearchWord(_searchController.text, langCode);
    if (word.isEmpty) return;

    if (word.length > 60 ||
        !RegExp(r"^[\p{L}\s\-']+$", unicode: true).hasMatch(word)) {
      setState(() {
        _error = 'Please enter a valid word.';
        _result = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _audioUrl = null;
      _activeSources.clear();
    });
    _focusNode.unfocus();

    try {
      final code = langCode;
      final isEnglish = code == 'en';
      final futures = await Future.wait([
        _fetchGeneral(word, code),
        isEnglish ? _fetchCollegiate(word) : Future<Map<String, dynamic>?>.value(null),
        isEnglish ? _fetchMedical(word) : Future<Map<String, dynamic>?>.value(null),
        isEnglish ? _fetchLegal(word) : Future<Map<String, dynamic>?>.value(null),
        _fetchCS(word, code),
      ]);

      final generalResult = futures[0];
      final collegiateResult = futures[1];
      final medicalResult = futures[2];
      final legalResult = futures[3];
      final csResult = futures[4];

      final List<Map<String, dynamic>> aggregatedMeanings = [];
      final activeSources = <_ResultSource>{};
      String wordTitle = word;
      String phoneticToUse = '';
      String originToUse = '';
      final List<dynamic> phoneticsToUse = [];

      void processResult(Map<String, dynamic>? res, _ResultSource source) {
        if (res == null) return;
        activeSources.add(source);

        wordTitle = res['word'] ?? wordTitle;
        if (phoneticToUse.isEmpty) phoneticToUse = res['phonetic'] ?? '';
        final o = res['origin'] as String?;
        if (originToUse.isEmpty && o != null && o.isNotEmpty) originToUse = o;
        if (phoneticsToUse.isEmpty && res['phonetics'] != null) {
          phoneticsToUse.addAll(res['phonetics'] as List<dynamic>);
        }

        for (final m in (res['meanings'] as List<dynamic>? ?? [])) {
          final map = Map<String, dynamic>.from(m as Map<String, dynamic>);
          map['_source'] = source.name;
          aggregatedMeanings.add(map);
        }
      }

      processResult(generalResult, _ResultSource.general);
      processResult(collegiateResult, _ResultSource.general);
      processResult(medicalResult, _ResultSource.medical);
      processResult(legalResult, _ResultSource.legal);
      processResult(csResult, _ResultSource.cs);

      if (aggregatedMeanings.isNotEmpty) {
        setState(() {
          _activeSources
            ..clear()
            ..addAll(activeSources);
          _result = {
            'word': wordTitle,
            'phonetic': phoneticToUse,
            'origin': originToUse,
            'phonetics': phoneticsToUse,
            'meanings': aggregatedMeanings,
          };
        });

        AnalyticsService.instance.recordDictionaryLookup(word);
        await DictionarySearchHistoryService.instance.recordSearch(
          word: word,
          langCode: code,
        );
        await _loadRecentSearches();

        if (generalResult != null) {
          _extractAudio(generalResult);
        } else if (collegiateResult != null) {
          _extractAudio(collegiateResult);
        } else if (medicalResult != null) {
          _extractAudio(medicalResult);
        } else if (legalResult != null) {
          _extractAudio(legalResult);
        } else if (csResult != null) {
          _extractAudio(csResult);
        }
      } else {
        setState(() => _error = _composeError(word, futures));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  FETCH — General (Wiktionary via freedictionaryapi.com)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<Map<String, dynamic>?> _fetchGeneral(
    String word,
    String langCode,
  ) async {
    try {
      final uri = Uri.parse(
        'https://freedictionaryapi.com/api/v1/entries/$langCode/${Uri.encodeComponent(word)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _parseFreeDictionaryApi(data, word, langCode);
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _parseFreeDictionaryApi(
    Map<String, dynamic> data,
    String fallbackWord,
    String langCode,
  ) {
    final entries = data['entries'] as List<dynamic>? ?? [];
    if (entries.isEmpty) return null;

    final word = (data['word'] as String?)?.trim();
    final title = (word != null && word.isNotEmpty) ? word : fallbackWord;

    String? languageName;
    String phonetic = '';
    final phonetics = <Map<String, dynamic>>[];
    final meanings = <Map<String, dynamic>>[];

    for (final raw in entries) {
      if (raw is! Map<String, dynamic>) continue;
      languageName ??= (raw['language'] as Map?)?['name'] as String?;

      if (phonetic.isEmpty) {
        for (final p in (raw['pronunciations'] as List<dynamic>? ?? [])) {
          if (p is! Map<String, dynamic>) continue;
          final text = (p['text'] as String?)?.trim() ?? '';
          if (text.isEmpty) continue;
          phonetic = text;
          phonetics.add({'text': text, 'audio': ''});
          break;
        }
      }

      final part = (raw['partOfSpeech'] as String?)?.trim() ?? 'definition';
      final definitions = <Map<String, dynamic>>[];
      for (final sense in (raw['senses'] as List<dynamic>? ?? [])) {
        if (sense is! Map<String, dynamic>) continue;
        final def = (sense['definition'] as String?)?.trim() ?? '';
        if (def.isEmpty) continue;
        final examples = sense['examples'] as List<dynamic>? ?? [];
        final example =
            examples.isNotEmpty ? (examples.first as String?)?.trim() : null;
        definitions.add({
          'definition': def,
          if (example != null && example.isNotEmpty) 'example': example,
        });
      }

      if (definitions.isEmpty) continue;

      meanings.add({
        'partOfSpeech': part,
        'definitions': definitions,
        'synonyms': (raw['synonyms'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        'antonyms': (raw['antonyms'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
      });
    }

    if (meanings.isEmpty) return null;

    final langLabel = languageName ?? langCode.toUpperCase();
    return {
      'word': title,
      'phonetic': phonetic,
      'phonetics': phonetics,
      'origin': 'Wiktionary ($langLabel)',
      'meanings': meanings,
    };
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  FETCH â€” Merriam-Webster Medical
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<Map<String, dynamic>?> _fetchCollegiate(String word) async {
    return _fetchMerriamWebsterReference(
      word: word,
      reference: 'collegiate',
      apiKey: _mwCollegiateKey,
      originLabel: 'Merriam-Webster Collegiate',
    );
  }

  Future<Map<String, dynamic>?> _fetchMedical(String word) async {
    return _fetchMerriamWebsterReference(
      word: word,
      reference: 'medical',
      apiKey: _mwMedicalKey,
      originLabel: 'Merriam-Webster Medical',
    );
  }

  /// Legal requires its own key at dictionaryapi.com (collegiate key does not work).
  Future<Map<String, dynamic>?> _fetchLegal(String word) async {
    return _fetchMerriamWebsterReference(
      word: word,
      reference: 'legal',
      apiKey: _mwLegalKey,
      originLabel: 'Merriam-Webster Legal',
    );
  }

  Future<Map<String, dynamic>?> _fetchMerriamWebsterReference({
    required String word,
    required String reference,
    required String apiKey,
    required String originLabel,
  }) async {
    if (apiKey.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://www.dictionaryapi.com/api/v3/references/$reference/json/${Uri.encodeComponent(word)}?key=$apiKey',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data[0] is Map) {
          final parsed =
              _parseMerriamWebster(data[0] as Map<String, dynamic>, word);
          if ((parsed['origin'] as String? ?? '').isEmpty) {
            parsed['origin'] = originLabel;
          }
          return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  FETCH â€” Technical (Wikipedia)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<Map<String, dynamic>?> _fetchCS(String word, String langCode) async {
    try {
      final wikiLang = langCode == 'zh' ? 'zh' : langCode;
      final uri = Uri.parse(
        'https://$wikiLang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(word)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final extract = data['extract'] as String?;
        if (extract != null && extract.isNotEmpty) {
          return {
            'word': data['title'] ?? word,
            'phonetic': '',
            'phonetics': [],
            'origin': 'Wikipedia (${wikiLang.toUpperCase()})',
            'meanings': [
              {
                'partOfSpeech': 'concept (technical)',
                'definitions': [
                  {'definition': extract},
                ],
                'synonyms': [],
                'antonyms': [],
              },
            ],
          };
        }
      }
    } catch (_) {}
    return null;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  HELPERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _composeError(String word, List<dynamic> futures) {
    return 'No results found for "$word".\n\nCheck the spelling or try a related term.';
  }

  // â”€â”€ Parse MW response into shared result format â”€â”€â”€â”€â”€â”€â”€
  Map<String, dynamic> _parseMerriamWebster(
    Map<String, dynamic> entry,
    String word,
  ) {
    final hwi = entry['hwi'] as Map<String, dynamic>? ?? {};
    final prs = hwi['prs'] as List<dynamic>? ?? [];
    final phonetic = prs.isNotEmpty
        ? (prs[0] as Map<String, dynamic>)['mw'] as String? ?? ''
        : '';

    String audioUrl = '';
    if (prs.isNotEmpty) {
      final sound =
          (prs[0] as Map<String, dynamic>)['sound'] as Map<String, dynamic>?;
      if (sound != null) {
        final audio = sound['audio'] as String? ?? '';
        if (audio.isNotEmpty) {
          final subdir = audio.startsWith('bix')
              ? 'bix'
              : audio.startsWith('gg')
              ? 'gg'
              : audio[0];
          audioUrl =
              'https://media.merriam-webster.com/audio/prons/en/us/mp3/$subdir/$audio.mp3';
        }
      }
    }

    final List<Map<String, dynamic>> meanings = [];
    final defs = entry['def'] as List<dynamic>? ?? [];
    for (final def in defs) {
      final sseq =
          (def as Map<String, dynamic>)['sseq'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> definitions = [];
      for (final senseGroup in sseq) {
        for (final sense in (senseGroup as List<dynamic>)) {
          if (sense is List && sense.length >= 2 && sense[0] == 'sense') {
            final senseData = sense[1] as Map<String, dynamic>;
            final dt = senseData['dt'] as List<dynamic>? ?? [];
            for (final part in dt) {
              if (part is List && part[0] == 'text') {
                final raw = part[1] as String;
                final clean = raw
                    .replaceAll(RegExp(r'\{[^}]*\}'), '')
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                if (clean.isNotEmpty) {
                  definitions.add({'definition': clean});
                }
              }
            }
          }
        }
      }
      if (definitions.isNotEmpty) {
        meanings.add({
          'partOfSpeech': entry['fl'] as String? ?? '',
          'definitions': definitions,
          'synonyms': [],
          'antonyms': [],
        });
        break;
      }
    }

    return {
      'word': word,
      'phonetic': phonetic,
      'phonetics': audioUrl.isNotEmpty
          ? [
              {'text': phonetic, 'audio': audioUrl},
            ]
          : [],
      'origin': '',
      'meanings': meanings,
    };
  }

  void _extractAudio(Map<String, dynamic> data) {
    final phonetics = data['phonetics'] as List<dynamic>? ?? [];
    for (final p in phonetics) {
      final audio = (p as Map<String, dynamic>)['audio'] as String?;
      if (audio != null && audio.isNotEmpty) {
        setState(
          () => _audioUrl = audio.startsWith('//') ? 'https:$audio' : audio,
        );
        return;
      }
    }
  }

  Future<void> _playAudio() async {
    if (_audioUrl == null || _isPlaying) return;
    try {
      setState(() => _isPlaying = true);
      await _audioPlayer.setUrl(_audioUrl!);
      await _audioPlayer.play();
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) setState(() => _isPlaying = false);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  String get _phonetic {
    if (_result == null) return '';
    final p = _result!['phonetic'] as String?;
    if (p != null && p.isNotEmpty) return p;
    for (final ph in (_result!['phonetics'] as List<dynamic>? ?? [])) {
      final text = (ph as Map<String, dynamic>)['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
    }
    return '';
  }

  String get _origin => _result?['origin'] as String? ?? '';

  List<Map<String, dynamic>> get _meanings =>
      (_result?['meanings'] as List<dynamic>? ?? [])
          .map((m) => m as Map<String, dynamic>)
          .toList();

  List<String> _getSynonyms() {
    final syns = <String>{};
    for (final m in _meanings) {
      for (final s in (m['synonyms'] as List<dynamic>? ?? [])) {
        syns.add(s as String);
      }
      for (final d in (m['definitions'] as List<dynamic>? ?? [])) {
        for (final s in ((d as Map)['synonyms'] as List<dynamic>? ?? [])) {
          syns.add(s as String);
        }
      }
    }
    return syns.take(8).toList();
  }

  Widget _sourceChip(_ResultSource source, LanguageProvider lang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4B9EFF).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 12, color: const Color(0xFF4B9EFF)),
          const SizedBox(width: 4),
          Text(
            lang.t(source.labelKey()),
            style: const TextStyle(
              color: Color(0xFF4B9EFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches(LanguageProvider lang, String langCode) {
    if (_recentSearches.isEmpty) {
      return const SizedBox.shrink();
    }

    final forLang = _recentSearches
        .where((e) => e.langCode == langCode)
        .take(12)
        .toList();
    if (forLang.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lang.t('dictionary_recent_searches'),
            style: TextStyle(
              color: VoxColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: forLang.map((entry) {
              return GestureDetector(
                onTap: () {
                  _searchController.text = entry.word;
                  _search(langCode);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: VoxColors.cardFill(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: VoxColors.border(context)),
                  ),
                  child: Text(
                    entry.word,
                    style: TextStyle(
                      color: VoxColors.onBg(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<String> _getAntonyms() {
    final ants = <String>{};
    for (final m in _meanings) {
      for (final a in (m['antonyms'] as List<dynamic>? ?? [])) {
        ants.add(a as String);
      }
      for (final d in (m['definitions'] as List<dynamic>? ?? [])) {
        for (final a in ((d as Map)['antonyms'] as List<dynamic>? ?? [])) {
          ants.add(a as String);
        }
      }
    }
    return ants.take(8).toList();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final langCode = _apiLangCode[lang.selectedLanguage] ?? 'en';

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Text(
              'VOX',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: VoxColors.onBg(context),
                letterSpacing: 5,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: VoxColors.primary(context),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                lang.t('nav_dictionary').toUpperCase(),
                style: TextStyle(
                  color: VoxColors.onPrimary(context),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: VoxColors.onBg(context).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  lang.selectedLanguage,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: VoxColors.textSecondary(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          // â”€â”€ Search bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    maxLength: 60,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(langCode),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? lang.t('search_voice_listening')
                          : lang.t('dictionary_search_hint'),
                      counterText: '',
                      prefixIcon: Icon(Icons.search, size: 20, color: VoxColors.textHint(context)),
                      filled: true,
                      fillColor: _isListening ? VoxColors.onBg(context).withValues(alpha: 0.12) : VoxColors.cardFill(context),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: VoxColors.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: VoxColors.border(context)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Mic button
                GestureDetector(
                  onTap: () => _startVoiceSearch(langCode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isListening
                            ? VoxColors.danger.withValues(alpha: 0.8)
                            : VoxColors.onBg(context).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop_rounded
                            : Icons.mic_none_rounded,
                        color: _isListening ? Colors.white : VoxColors.onBg(context).withValues(alpha: 0.7),
                        size: 22,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // Search button
                GestureDetector(
                  onTap: () => _search(langCode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: VoxColors.primary(context),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: VoxColors.primary(context).withValues(alpha: 0.3), blurRadius: 8)
                      ],
                    ),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            Icons.arrow_forward,
                            color: VoxColors.onPrimary(context),
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          _buildRecentSearches(lang, langCode),

          // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_result == null && !_loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📖', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text(
                      lang.t('dictionary_vox_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xDD0A0E1A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lang.t('dictionary_tagline'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => _startVoiceSearch(langCode),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Color(0xFF0A0E1A),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mic_none_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              lang.t('tap_to_speak'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_result != null)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // â”€â”€ Word card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Color(0xFF0A0E1A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _result!['word'] as String? ?? '',
                                      style: TextStyle(
                                        color: Color(0xFFF0F4FF),
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: _activeSources
                                          .map((s) => _sourceChip(s, lang))
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                              // Audio button â€” auto-plays for accessibility
                              if (_audioUrl != null)
                                GestureDetector(
                                  onTap: _playAudio,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4B9EFF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _isPlaying
                                          ? Icons.volume_up_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Color(0xFF0A0E1A),
                                      size: 22,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_phonetic.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _phonetic,
                              style: TextStyle(
                                color: Color(0xFF4B9EFF),
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // â”€â”€ Origin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (_origin.isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.history_edu_rounded,
                        label: 'ORIGIN',
                        child: Text(
                          _origin,
                          style: TextStyle(
                            color: Color(0xFF1c2333),
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // â”€â”€ Meanings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    ..._meanings.map((meaning) {
                      final pos = meaning['partOfSpeech'] as String? ?? '';
                      final source =
                          _resultSourceFromKey(meaning['_source'] as String?);
                      final defs =
                          (meaning['definitions'] as List<dynamic>? ?? [])
                              .take(3)
                              .toList();
                      final label = pos.isNotEmpty
                          ? pos.toUpperCase()
                          : 'DEFINITION';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _sectionCard(
                          icon: source?.icon ?? _posIcon(pos),
                          label: _activeSources.length > 1 && source != null
                              ? '$label · ${lang.t(source.labelKey())}'
                              : label,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: defs.asMap().entries.map((entry) {
                              final i = entry.key + 1;
                              final def = entry.value as Map<String, dynamic>;
                              final definition =
                                  def['definition'] as String? ?? '';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(
                                        top: 2,
                                        right: 10,
                                      ),
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF4B9EFF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '$i',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0A0E1A),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        definition,
                                        style: TextStyle(
                                          color: Color(0xFF1c2333),
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    }),

                    // â”€â”€ Synonyms â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (_getSynonyms().isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.compare_arrows_rounded,
                        label: 'SYNONYMS',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _getSynonyms()
                              .map(
                                (s) => GestureDetector(
                                  onTap: () {
                                    _searchController.text = s;
                                    _search(langCode);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF4B9EFF,
                                      ).withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFF4B9EFF),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      s,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xDD0A0E1A),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // â”€â”€ Antonyms â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (_getAntonyms().isNotEmpty)
                      _sectionCard(
                        icon: Icons.swap_horiz_rounded,
                        label: 'ANTONYMS',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _getAntonyms()
                              .map(
                                (a) => GestureDetector(
                                  onTap: () {
                                    _searchController.text = a;
                                    _search(langCode);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.grey.shade400,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      a,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),

      bottomNavigationBar: BottomAppBar(
        color: VoxColors.bottomBar(context),
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(
                Icons.home,
                lang.t('nav_home'),
                VoxColors.textSecondary(context),
                onTap: () => Navigator.pushReplacementNamed(context, '/home'),
              ),
              _navItem(
                Icons.note_alt_outlined,
                lang.t('nav_notes'),
                VoxColors.textSecondary(context),
                onTap: () => Navigator.pushReplacementNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                lang.t('nav_dictionary'),
                VoxColors.onSurface(context),
              ),
              _navItem(
                Icons.menu,
                lang.t('nav_menu'),
                VoxColors.textSecondary(context),
                onTap: () => Navigator.pushReplacementNamed(context, '/menu'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: VoxColors.fabBackground(context),
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: Icon(
          Icons.file_upload_outlined,
          color: VoxColors.onPrimary(context),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Color(0x8A0A0E1A)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0x730A0E1A),
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  IconData _posIcon(String pos) {
    switch (pos.toLowerCase()) {
      case 'noun':
        return Icons.label_outline_rounded;
      case 'verb':
        return Icons.play_circle_outline_rounded;
      case 'adjective':
        return Icons.auto_awesome_outlined;
      case 'adverb':
        return Icons.speed_rounded;
      default:
        return Icons.notes_rounded;
    }
  }

  Widget _navItem(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

