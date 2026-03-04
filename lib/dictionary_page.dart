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

// ── Dictionary modes ──────────────────────────────────
enum DictMode { general, medical, cs, law, math }

extension DictModeInfo on DictMode {
  String get label {
    switch (this) {
      case DictMode.general: return 'General';
      case DictMode.medical: return 'Medical';
      case DictMode.cs:      return 'Computer Science';
      case DictMode.law:     return 'Law';
      case DictMode.math:    return 'Mathematics';
    }
  }

  String get emoji {
    switch (this) {
      case DictMode.general: return '🌐';
      case DictMode.medical: return '🏥';
      case DictMode.cs:      return '💻';
      case DictMode.law:     return '⚖️';
      case DictMode.math:    return '📐';
    }
  }

  String get hint {
    switch (this) {
      case DictMode.general: return 'Search any word';
      case DictMode.medical: return 'e.g. tachycardia, hypertension';
      case DictMode.cs:      return 'e.g. algorithm, recursion';
      case DictMode.law:     return 'e.g. tort, habeas corpus';
      case DictMode.math:    return 'e.g. derivative, eigenvalue';
    }
  }

  // Merriam-Webster Medical API key — replace with yours from dictionaryapi.com
  static const String _mwMedicalKey = 'YOUR_MW_MEDICAL_API_KEY';

  bool get usesMerriamWebster => this == DictMode.medical;
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

  DictMode _selectedMode = DictMode.general;
  Map<String, dynamic>? _result;
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

  // ── Voice search ──────────────────────────────────────
  Future<void> _startVoiceSearch(String langCode) async {
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
        final firstWord = val.recognizedWords.trim().split(' ').first;
        if (mounted) setState(() => _searchController.text = firstWord);
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: true,
    );
  }

  // ── Search — routes to correct API ───────────────────
  Future<void> _search(String langCode) async {
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
      if (_selectedMode == DictMode.medical) {
        await _searchMerriamWebsterMedical(word);
      } else {
        await _searchFreeDictionary(word, langCode);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Free Dictionary API (general, CS, law, math) ──────
  Future<void> _searchFreeDictionary(String word, String langCode) async {
    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/$langCode/${Uri.encodeComponent(word)}',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          setState(() => _result = data[0] as Map<String, dynamic>);
          _extractAudio(data[0] as Map<String, dynamic>);
        } else {
          setState(() => _error = 'No results found.');
        }
      } else if (response.statusCode == 404) {
        setState(() => _error =
            'Word not found. Check the spelling or try another word.');
      } else if (response.statusCode == 429) {
        setState(() => _error =
            'Too many requests. Please wait a moment and try again.');
      } else {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } on Exception catch (e) {
      final msg = e.toString();
      setState(() => _error =
          msg.contains('SocketException') || msg.contains('TimeoutException')
              ? 'No internet connection.'
              : 'Something went wrong. Please try again.');
    }
  }

  // ── Merriam-Webster Medical API ───────────────────────
  Future<void> _searchMerriamWebsterMedical(String word) async {
    const apiKey = DictModeInfo._mwMedicalKey;
    if (apiKey == 'YOUR_MW_MEDICAL_API_KEY') {
      setState(() => _error =
          'Medical dictionary API key not configured.\nAdd your key from dictionaryapi.com.');
      return;
    }

    try {
      final uri = Uri.parse(
        'https://www.dictionaryapi.com/api/v3/references/medical/json/${Uri.encodeComponent(word)}?key=$apiKey',
      );
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // MW returns a list of strings when word not found
        if (data is List && data.isNotEmpty && data[0] is String) {
          setState(() => _error =
              'Word not found. Did you mean: ${(data as List<dynamic>).take(5).join(', ')}?');
          return;
        }

        if (data is List && data.isNotEmpty && data[0] is Map) {
          setState(() => _result = _parseMerriamWebster(
              data[0] as Map<String, dynamic>, word));
          _extractAudio(_result!);
        } else {
          setState(() => _error = 'No results found.');
        }
      } else if (response.statusCode == 403) {
        setState(() =>
            _error = 'Invalid API key. Check your Merriam-Webster key.');
      } else if (response.statusCode == 429) {
        setState(() => _error =
            'Daily limit reached (1,000 queries/day). Try again tomorrow.');
      } else {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } on Exception catch (e) {
      final msg = e.toString();
      setState(() => _error =
          msg.contains('SocketException') || msg.contains('TimeoutException')
              ? 'No internet connection.'
              : 'Something went wrong. Please try again.');
    }
  }

  // ── Parse MW response into shared result format ───────
  Map<String, dynamic> _parseMerriamWebster(
      Map<String, dynamic> entry, String word) {
    final hwi = entry['hwi'] as Map<String, dynamic>? ?? {};
    final prs = hwi['prs'] as List<dynamic>? ?? [];
    final phonetic = prs.isNotEmpty
        ? (prs[0] as Map<String, dynamic>)['mw'] as String? ?? ''
        : '';

    // Extract audio from MW format
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

    // Build meanings from MW 'def' structure
    final List<Map<String, dynamic>> meanings = [];
    final defs = entry['def'] as List<dynamic>? ?? [];
    for (final def in defs) {
      final sseq = (def as Map<String, dynamic>)['sseq'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> definitions = [];
      for (final senseGroup in sseq) {
        for (final sense in (senseGroup as List<dynamic>)) {
          if (sense is List && sense.length >= 2 && sense[0] == 'sense') {
            final senseData = sense[1] as Map<String, dynamic>;
            final dt = senseData['dt'] as List<dynamic>? ?? [];
            for (final part in dt) {
              if (part is List && part[0] == 'text') {
                final raw = part[1] as String;
                // Strip MW markup tags like {bc}, {it}, {/it}, {sx|...||}
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
        break; // one meaning block per entry is enough
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

  // ── Result helpers ────────────────────────────────────
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
      for (final s in (m['synonyms'] as List<dynamic>? ?? [])) syns.add(s as String);
      for (final d in (m['definitions'] as List<dynamic>? ?? [])) {
        for (final s in ((d as Map)['synonyms'] as List<dynamic>? ?? [])) syns.add(s as String);
      }
    }
    return syns.take(8).toList();
  }

  List<String> _getAntonyms() {
    final ants = <String>{};
    for (final m in _meanings) {
      for (final a in (m['antonyms'] as List<dynamic>? ?? [])) ants.add(a as String);
      for (final d in (m['definitions'] as List<dynamic>? ?? [])) {
        for (final a in ((d as Map)['antonyms'] as List<dynamic>? ?? [])) ants.add(a as String);
      }
    }
    return ants.take(8).toList();
  }

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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          // ── Mode dropdown ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<DictMode>(
                  value: _selectedMode,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  iconEnabledColor: const Color(0xFFF3E5AB),
                  style: const TextStyle(
                      color: Color(0xFFF3E5AB),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  onChanged: (mode) {
                    if (mode != null) {
                      setState(() {
                        _selectedMode = mode;
                        _result = null;
                        _error = null;
                        _audioUrl = null;
                        _searchController.clear();
                      });
                    }
                  },
                  items: DictMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Row(
                        children: [
                          Text(mode.emoji,
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 10),
                          Text(mode.label),
                          if (mode == DictMode.medical) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4B96A)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('MW',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFFD4B96A),
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // ── Medical API key notice ──────────────────────
          if (_selectedMode == DictMode.medical) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.black.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.black54, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Powered by Merriam-Webster Medical. Free API key needed from dictionaryapi.com.',
                        style: TextStyle(
                            color: Colors.black54,
                            fontSize: 10,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Search bar ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    maxLength: 60,
                    textInputAction: TextInputAction.search,
                    onSubmitted: unsupported
                        ? null
                        : (_) => _search(langCode!),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : unsupported
                              ? 'Not available in Chinese'
                              : _selectedMode.hint,
                      counterText: '',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: _isListening
                          ? Colors.grey[200]
                          : Colors.white,
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
                    onTap: () => _startVoiceSearch(langCode!),
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
                        color: _isListening ? Colors.white : Colors.black87,
                        size: 22,
                      ),
                    ),
                  ),

                const SizedBox(width: 8),

                // Search button
                GestureDetector(
                  onTap: unsupported ? null : () => _search(langCode!),
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
                      const Text('Chinese dictionary\nnot available yet',
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
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13),
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
                    Text(_selectedMode.emoji,
                        style: const TextStyle(fontSize: 44)),
                    const SizedBox(height: 12),
                    Text(
                      '${_selectedMode.label} Dictionary',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedMode.hint,
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    if (!unsupported)
                      GestureDetector(
                        onTap: () => _startVoiceSearch(langCode!),
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
                    // Word card
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
                                    // Mode badge
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD4B96A)
                                            .withOpacity(0.2),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${_selectedMode.emoji} ${_selectedMode.label}',
                                        style: const TextStyle(
                                            color: Color(0xFFD4B96A),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

                    // Origin
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

                    // Meanings
                    ..._meanings.map((meaning) {
                      final pos =
                          meaning['partOfSpeech'] as String? ?? '';
                      final defs =
                          (meaning['definitions'] as List<dynamic>? ?? [])
                              .take(3)
                              .toList();
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
                                      width: 20, height: 20,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFD4B96A),
                                          shape: BoxShape.circle),
                                      child: Center(
                                        child: Text('$i',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
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

                    // Synonyms
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
                                      _search(langCode!);
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

                    // Antonyms
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
                                      _search(langCode!);
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
              _navItem(Icons.book, lang.t('nav_dictionary'), Colors.white),
              _navItem(Icons.menu, lang.t('nav_menu'), Colors.grey[400]!,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, '/menu')),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: const Icon(Icons.file_upload_outlined, color: Colors.white),
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
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
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
      case 'noun':       return Icons.label_outline_rounded;
      case 'verb':       return Icons.play_circle_outline_rounded;
      case 'adjective':  return Icons.auto_awesome_outlined;
      case 'adverb':     return Icons.speed_rounded;
      default:           return Icons.notes_rounded;
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