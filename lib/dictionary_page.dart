import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'language_provider.dart';

const Map<String, String?> _apiLangCode = {
  'English': 'en',
  'Spanish': 'es',
  'French':  'fr',
  'Arabic':  'ar',
  'Turkish': 'tr',
  'Chinese': null,
};

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
      // Search with whatever was captured
      final word = _searchController.text.trim();
      if (word.isNotEmpty) _search(langCode);
      return;
    }

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission denied'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final available = await _speech.initialize(
      onError: (e) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) {
            setState(() => _isListening = false);
            // Auto-search when speech ends
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
          backgroundColor: Colors.orange,
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
        // Show word live as user speaks
        final words = val.recognizedWords.trim();
        // Only take the first word — dictionary searches are single words
        final firstWord = words.split(' ').first;
        if (mounted) {
          setState(() => _searchController.text = firstWord);
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      cancelOnError: true,
    );
  }

  // ── Dictionary search ─────────────────────────────────
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _extractAudio(Map<String, dynamic> data) {
    final phonetics = data['phonetics'] as List<dynamic>? ?? [];
    for (final p in phonetics) {
      final audio = (p as Map<String, dynamic>)['audio'] as String?;
      if (audio != null && audio.isNotEmpty) {
        setState(() => _audioUrl =
            audio.startsWith('//') ? 'https:$audio' : audio);
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
                borderRadius: BorderRadius.circular(6),
              ),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        ],
      ),

      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    maxLength: 60,
                    textInputAction: TextInputAction.search,
                    onSubmitted: unsupported ? null : (_) => _search(langCode!),
                    decoration: InputDecoration(
                      hintText: _isListening
                          ? 'Listening...'
                          : unsupported
                              ? 'Dictionary not available in Chinese'
                              : 'Search a word in ${lang.selectedLanguage}...',
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
                        borderSide: _isListening
                            ? BorderSide(color: Colors.grey[400]!, width: 1.5)
                            : BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
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
                        _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
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
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                  ),
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

          // ── Unsupported ─────────────────────────────────
          if (unsupported)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🈚', style: TextStyle(fontSize: 48)),
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

          // ── Error ───────────────────────────────────────
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
                              fontSize: 15,
                              height: 1.5)),
                    ],
                  ),
                ),
              ),
            )

          // ── Empty state ─────────────────────────────────
          else if (_result == null && !_loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 56,
                        color: Colors.black.withOpacity(0.12)),
                    const SizedBox(height: 14),
                    Text(
                      'Search or say a word\nin ${lang.selectedLanguage}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    // Mic hint button
                    if (!unsupported)
                      GestureDetector(
                        onTap: () => _startVoiceSearch(langCode!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(30),
                          ),
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

          // ── Results ─────────────────────────────────────
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
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  _result!['word'] as String? ?? '',
                                  style: const TextStyle(
                                      color: Color(0xFFF3E5AB),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5),
                                ),
                              ),
                              if (_audioUrl != null)
                                GestureDetector(
                                  onTap: _playAudio,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD4B96A),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
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
                                    fontSize: 16,
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
                          label: pos.toUpperCase(),
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
                                        shape: BoxShape.circle,
                                      ),
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
                                            color: const Color(0xFFD4B96A),
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
                                        color: Colors.red.shade50,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: Colors.red.shade200,
                                            width: 1),
                                      ),
                                      child: Text(a,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red.shade700)),
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