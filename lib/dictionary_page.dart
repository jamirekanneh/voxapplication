import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'language_provider.dart';

// ── API language codes for dictionaryapi.dev ──────────
const Map<String, String?> _apiLangCode = {
  'English': 'en',
  'Spanish': 'es',
  'French':  'fr',
  'Arabic':  'ar',
  'Turkish': 'tr',
  'Chinese': null,
};

// MW Medical API key — get free from dictionaryapi.com
const String _mwMedicalKey = 'YOUR_MW_MEDICAL_API_KEY';

// ── Source label shown on result card ────────────────
enum _ResultSource { general, medical, cs, notFound }

extension _SourceInfo on _ResultSource {
  String get label {
    switch (this) {
      case _ResultSource.general:  return 'General';
      case _ResultSource.medical:  return 'Medical';
      case _ResultSource.cs:       return 'Technical';
      case _ResultSource.notFound: return '';
    }
  }
  String get emoji {
    switch (this) {
      case _ResultSource.general:  return '🌐';
      case _ResultSource.medical:  return '🏥';
      case _ResultSource.cs:       return '💻';
      case _ResultSource.notFound: return '';
    }
  }
}

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final TextEditingController _searchController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FocusNode _focusNode = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();

  Map<String, dynamic>? _result;
  _ResultSource _resultSource = _ResultSource.general;
  String? _error;
  bool _loading = false;
  bool _isPlaying = false;
  bool _isListening = false;
  String? _audioUrl;

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    _focusNode.dispose();
    _speech.stop();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  VOICE SEARCH
  // ─────────────────────────────────────────────
  Future<void> _startVoiceSearch(String? langCode) async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      final word = _searchController.text.trim();
      if (word.isNotEmpty) _search(langCode);
      return;
    }

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission denied'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final available = await _speech.initialize(
      onError: (e) { if (mounted) setState(() => _isListening = false); },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) {
            setState(() => _isListening = false);
            final word = _searchController.text.trim();
            if (word.isNotEmpty) _search(langCode);
          }
        }
      },
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Speech recognition not available on this device'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    setState(() { _isListening = true; _searchController.clear(); });
    final langProvider = context.read<LanguageProvider>();
    _speech.listen(
      localeId: langProvider.sttLocale,
      onResult: (val) {
        final text = val.recognizedWords.trim();
        if (mounted) setState(() => _searchController.text = text);
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: true,
    );
  }

  // ─────────────────────────────────────────────
  //  MAIN SEARCH — smart routing
  //
  //  Strategy:
  //  1. Fire general + medical requests in parallel
  //  2. If general returns good definitions → use it
  //  3. If general returns nothing / weak → prefer medical if it found it
  //  4. If both fail → show error with suggestions
  // ─────────────────────────────────────────────
  Future<void> _search(String? langCode) async {
    final word = _searchController.text.trim().toLowerCase();
    if (word.isEmpty) return;

    if (word.length > 60 ||
        !RegExp(r"^[\p{L}\s\-']+$", unicode: true).hasMatch(word)) {
      setState(() { _error = 'Please enter a valid word.'; _result = null; });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _audioUrl = null;
    });
    _focusNode.unfocus();

    try {
      // ── Fire both lookups simultaneously ──────────────
      final futures = await Future.wait([
        _fetchGeneral(word, langCode ?? 'en'),
        _fetchMedical(word),
        _fetchCS(word),
      ]);

      final generalResult = futures[0];
      final medicalResult = futures[1];
      final csResult = futures[2];

      final List<Map<String, dynamic>> aggregatedMeanings = [];
      String wordTitle = word;
      String phoneticToUse = '';
      String originToUse = '';
      final List<dynamic> phoneticsToUse = [];

      void processResult(Map<String, dynamic>? res) {
        if (res == null) return;
        
        wordTitle = res['word'] ?? wordTitle;
        if (phoneticToUse.isEmpty) phoneticToUse = res['phonetic'] ?? '';
        final o = res['origin'] as String?;
        if (originToUse.isEmpty && o != null && o.isNotEmpty) originToUse = o;
        if (phoneticsToUse.isEmpty && res['phonetics'] != null) {
          phoneticsToUse.addAll(res['phonetics'] as List<dynamic>);
        }

        final meaningsList = (res['meanings'] as List<dynamic>? ?? []).map((m) => m as Map<String, dynamic>);
        aggregatedMeanings.addAll(meaningsList);
      }

      processResult(generalResult);
      processResult(medicalResult);
      processResult(csResult);

      _ResultSource determinePrimarySource() {
          if (medicalResult != null) return _ResultSource.medical;
          
          int medicalScore = 0;
          int techScore = 0;
          
          final techKeywords = ['computer', 'software', 'programming', 'algorithm', 'network', 'computing', 'data structure', 'code ', 'developer', 'hardware', 'app ', 'internet', 'technology'];
          final medKeywords = ['medical', 'disease', 'anatomy', 'blood', 'heart', 'organ ', 'virus', 'infection', 'syndrome', 'clinical', 'hospital', 'surgery', 'patient', 'treatment', 'drug', 'medicine', 'illness', 'muscle'];

          final textToScan = aggregatedMeanings.toString().toLowerCase();
          for (var kw in techKeywords) { if (textToScan.contains(kw)) techScore += 2; }
          for (var kw in medKeywords) { if (textToScan.contains(kw)) medicalScore += 2; }
          
          final w = word.toLowerCase();
          if (['python', 'java', 'html', 'css', 'react', 'flutter', 'dart', 'api', 'computer', 'structure'].contains(w)) techScore += 10;
          if (['heart', 'brain', 'liver', 'cancer', 'flu', 'covid', 'ill', 'sick', 'pain'].contains(w)) medicalScore += 10;

          if (techScore > 0 && techScore > medicalScore) return _ResultSource.cs;
          if (medicalScore > 0 && medicalScore > techScore) return _ResultSource.medical;
          return _ResultSource.general;
      }

      if (aggregatedMeanings.isNotEmpty) {
        setState(() {
           _resultSource = determinePrimarySource();
           _result = {
              'word': wordTitle,
              'phonetic': phoneticToUse,
              'origin': originToUse,
              'phonetics': phoneticsToUse,
              'meanings': aggregatedMeanings,
           };
        });
        
        if (generalResult != null) _extractAudio(generalResult);
        else if (medicalResult != null) _extractAudio(medicalResult);
        else if (csResult != null) _extractAudio(csResult);
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

  // ─────────────────────────────────────────────
  //  FETCH — General (dictionaryapi.dev)
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>?> _fetchGeneral(
      String word, String langCode) async {
    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/$langCode/${Uri.encodeComponent(word)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) return data[0] as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────────────────────
  //  FETCH — Merriam-Webster Medical
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>?> _fetchMedical(String word) async {
    if (_mwMedicalKey == 'YOUR_MW_MEDICAL_API_KEY') return null;
    try {
      final uri = Uri.parse(
        'https://www.dictionaryapi.com/api/v3/references/medical/json/${Uri.encodeComponent(word)}?key=$_mwMedicalKey',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data[0] is Map) {
          return _parseMerriamWebster(
              data[0] as Map<String, dynamic>, word);
        }
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────────────────────
  //  FETCH — Technical (Wikipedia)
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>?> _fetchCS(String word) async {
    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(word)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final extract = data['extract'] as String?;
        if (extract != null && extract.isNotEmpty) {
          return {
            'word': data['title'] ?? word,
            'phonetic': '',
            'phonetics': [],
            'origin': 'Wikipedia Encyclopedia',
            'meanings': [
              {
                'partOfSpeech': 'concept (technical)',
                'definitions': [{'definition': extract}],
                'synonyms': [],
                'antonyms': [],
              }
            ],
          };
        }
      }
    } catch (_) {}
    return null;
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────
  int _countDefinitions(Map<String, dynamic>? result) {
    if (result == null) return 0;
    int count = 0;
    for (final m in (result['meanings'] as List<dynamic>? ?? [])) {
      count +=
          ((m as Map<String, dynamic>)['definitions'] as List<dynamic>? ?? [])
              .length;
    }
    return count;
  }

  String _composeError(String word, List<dynamic> futures) {
    return 'No results found for "$word".\n\nCheck the spelling or try a related term.';
  }

  // ── Parse MW response into shared result format ───────
  Map<String, dynamic> _parseMerriamWebster(
      Map<String, dynamic> entry, String word) {
    final hwi = entry['hwi'] as Map<String, dynamic>? ?? {};
    final prs = hwi['prs'] as List<dynamic>? ?? [];
    final phonetic = prs.isNotEmpty
        ? (prs[0] as Map<String, dynamic>)['mw'] as String? ?? ''
        : '';

    String audioUrl = '';
    if (prs.isNotEmpty) {
      final sound = (prs[0] as Map<String, dynamic>)['sound']
          as Map<String, dynamic>?;
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
          ? [{'text': phonetic, 'audio': audioUrl}]
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
        setState(() =>
            _audioUrl = audio.startsWith('//') ? 'https:$audio' : audio);
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
        for (final s
            in ((d as Map)['synonyms'] as List<dynamic>? ?? [])) {
          syns.add(s as String);
        }
      }
    }
    return syns.take(8).toList();
  }

  List<String> _getAntonyms() {
    final ants = <String>{};
    for (final m in _meanings) {
      for (final a in (m['antonyms'] as List<dynamic>? ?? [])) {
        ants.add(a as String);
      }
      for (final d in (m['definitions'] as List<dynamic>? ?? [])) {
        for (final a
            in ((d as Map)['antonyms'] as List<dynamic>? ?? [])) {
          ants.add(a as String);
        }
      }
    }
    return ants.take(8).toList();
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final langCode = _apiLangCode[lang.selectedLanguage];
    final unsupported = langCode == null;

    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Text('VOX',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                    letterSpacing: 5)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                lang.t('nav_dictionary').toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFFF3E5AB),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2),
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
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(lang.selectedLanguage,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
              ),
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────
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
                    onSubmitted: unsupported ? null : (_) => _search(langCode),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : unsupported
                              ? 'Not available in Chinese'
                              : 'Search any word…',
                      counterText: '',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor:
                          _isListening ? Colors.grey[200] : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    enabled: !unsupported,
                  ),
                ),
                const SizedBox(width: 8),

                // Mic button
                if (!unsupported)
                  GestureDetector(
                    onTap: () => _startVoiceSearch(langCode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.red
                            : Colors.black.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop_rounded
                            : Icons.mic_none_rounded,
                        color:
                            _isListening ? Colors.white : Colors.black87,
                        size: 22,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // Search button
                GestureDetector(
                  onTap: unsupported ? null : () => _search(langCode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: unsupported ? Colors.grey[400] : Colors.black,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.arrow_forward,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ── Listening indicator ─────────────────────────
          if (_isListening)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(
                    'Listening in ${lang.selectedLanguage} — say a word',
                    style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),

          // ── Body ────────────────────────────────────────
          if (unsupported)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🈚',
                          style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      const Text(
                          'Chinese dictionary\nnot available yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              height: 1.4)),
                      const SizedBox(height: 10),
                      Text(
                        'Switch to English, Spanish, French,\nArabic, or Turkish in the Menu.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                              height: 1.5)),
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
                    const Text('📖',
                        style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text('VOX Dictionary',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87)),
                    const SizedBox(height: 6),
                    Text(
                      'General, medical, legal & technical\nall in one search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => _startVoiceSearch(langCode),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(30)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic_none_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Tap to speak',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
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
                    // ── Word card ────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _result!['word'] as String? ?? '',
                                      style: const TextStyle(
                                          color: Color(0xFFF3E5AB),
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD4B96A)
                                            .withOpacity(0.2),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${_resultSource.emoji} ${_resultSource.label} Dictionary',
                                        style: const TextStyle(
                                            color: Color(0xFFD4B96A),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Audio button — auto-plays for accessibility
                              if (_audioUrl != null)
                                GestureDetector(
                                  onTap: _playAudio,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFD4B96A),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Icon(
                                      _isPlaying
                                          ? Icons.volume_up_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 22,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (_phonetic.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(_phonetic,
                                style: const TextStyle(
                                    color: Color(0xFFD4B96A),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Origin ───────────────────────────────
                    if (_origin.isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.history_edu_rounded,
                        label: 'ORIGIN',
                        child: Text(_origin,
                            style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                                height: 1.6)),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Meanings ─────────────────────────────
                    ..._meanings.map((meaning) {
                      final pos =
                          meaning['partOfSpeech'] as String? ?? '';
                      final defs = (meaning['definitions']
                              as List<dynamic>? ??
                          []).take(3).toList();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _sectionCard(
                          icon: _posIcon(pos),
                          label: pos.isNotEmpty
                              ? pos.toUpperCase()
                              : 'DEFINITION',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: defs.asMap().entries.map((entry) {
                              final i = entry.key + 1;
                              final def =
                                  entry.value as Map<String, dynamic>;
                              final definition =
                                  def['definition'] as String? ?? '';
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(
                                          top: 2, right: 10),
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFD4B96A),
                                          shape: BoxShape.circle),
                                      child: Center(
                                        child: Text('$i',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w800,
                                                color: Colors.black)),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(definition,
                                          style: TextStyle(
                                              color: Colors.grey[800],
                                              fontSize: 13,
                                              height: 1.5)),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    }),

                    // ── Synonyms ─────────────────────────────
                    if (_getSynonyms().isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.compare_arrows_rounded,
                        label: 'SYNONYMS',
                        child: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: _getSynonyms()
                              .map((s) => GestureDetector(
                                    onTap: () {
                                      _searchController.text = s;
                                      _search(langCode);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD4B96A)
                                            .withOpacity(0.3),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color:
                                                const Color(0xFFD4B96A),
                                            width: 1),
                                      ),
                                      child: Text(s,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87)),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Antonyms ─────────────────────────────
                    if (_getAntonyms().isNotEmpty)
                      _sectionCard(
                        icon: Icons.swap_horiz_rounded,
                        label: 'ANTONYMS',
                        child: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: _getAntonyms()
                              .map((a) => GestureDetector(
                                    onTap: () {
                                      _searchController.text = a;
                                      _search(langCode);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: Colors.grey.shade400,
                                            width: 1),
                                      ),
                                      child: Text(a,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey[700])),
                                    ),
                                  ))
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
        color: Colors.grey[850],
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home, lang.t('nav_home'), Colors.grey[400]!,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/home')),
              _navItem(Icons.note_alt_outlined, lang.t('nav_notes'),
                  Colors.grey[400]!,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/notes')),
              const SizedBox(width: 48),
              _navItem(
                  Icons.book, lang.t('nav_dictionary'), Colors.white),
              _navItem(Icons.menu, lang.t('nav_menu'), Colors.grey[400]!,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/menu')),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child:
            const Icon(Icons.file_upload_outlined, color: Colors.white),
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
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: Colors.black54),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black45,
                    letterSpacing: 2)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  IconData _posIcon(String pos) {
    switch (pos.toLowerCase()) {
      case 'noun':      return Icons.label_outline_rounded;
      case 'verb':      return Icons.play_circle_outline_rounded;
      case 'adjective': return Icons.auto_awesome_outlined;
      case 'adverb':    return Icons.speed_rounded;
      default:          return Icons.notes_rounded;
    }
  }

  Widget _navItem(IconData icon, String label, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}