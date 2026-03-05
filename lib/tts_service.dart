import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  List<Map<String, String>> _availableVoices = [];
  Map<String, String>? _selectedVoice;

  bool isPlaying = false;
  bool isVisible = false;
  double speechRate = 1.0;
  double progress = 0.0;

  // Word-level highlight
  int wordStart = 0;
  int wordEnd = 0;

  // Sentence-level highlight
  int sentenceStart = 0;
  int sentenceEnd = 0;

  String? title;
  String? content;

  // Tracks char position so we can seek forward/back
  int _currentCharOffset = 0;

  List<Map<String, String>> get availableVoices => _availableVoices;
  Map<String, String>? get selectedVoice => _selectedVoice;

  TtsService() {
    _init();
  }

  Future<void> _init() async {
    // Let the TTS engine fully start before querying voices
    await _tts.awaitSpeakCompletion(true);

    _tts.setCompletionHandler(() {
      isPlaying = false;
      progress = 1.0;
      notifyListeners();
    });

    _tts.setProgressHandler((text, start, end, word) {
      final total = content?.length ?? 1;
      _currentCharOffset = start;
      if (total > 0) {
        progress = end / total;
        wordStart = start;
        wordEnd = end;
        // Find sentence boundaries around current word
        _updateSentenceBounds(start);
      }
      notifyListeners();
    });

    _tts.setErrorHandler((msg) {
      isPlaying = false;
      notifyListeners();
    });

    // Load voices after engine is ready
    await _loadVoices();
  }

  void _updateSentenceBounds(int charPos) {
    final text = content;
    if (text == null || text.isEmpty) return;

    // Find start of sentence (look back for . ! ?)
    int sStart = charPos;
    while (sStart > 0) {
      final ch = text[sStart - 1];
      if (ch == '.' || ch == '!' || ch == '?') break;
      sStart--;
    }
    // Skip leading whitespace
    while (sStart < charPos && text[sStart] == ' ') sStart++;

    // Find end of sentence
    int sEnd = charPos;
    while (sEnd < text.length) {
      final ch = text[sEnd];
      if (ch == '.' || ch == '!' || ch == '?') {
        sEnd++;
        break;
      }
      sEnd++;
    }

    sentenceStart = sStart;
    sentenceEnd = sEnd.clamp(0, text.length);
  }

  Future<void> _loadVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw != null) {
        // Accept ALL voices — no locale filter so user sees everything
        final all = (raw as List)
            .map<Map<String, String>>((v) {
              return {
                'name': v['name']?.toString() ?? '',
                'locale': v['locale']?.toString() ?? '',
              };
            })
            .where((v) => v['name']!.isNotEmpty)
            .toList();

        // Sort: put the app's supported locales first, rest after
        const priority = ['en', 'es', 'fr', 'ar', 'tr', 'zh'];
        all.sort((a, b) {
          final aP = priority.indexWhere(
            (p) => a['locale']!.toLowerCase().startsWith(p),
          );
          final bP = priority.indexWhere(
            (p) => b['locale']!.toLowerCase().startsWith(p),
          );
          final aIdx = aP == -1 ? 999 : aP;
          final bIdx = bP == -1 ? 999 : bP;
          return aIdx.compareTo(bIdx);
        });

        _availableVoices = all;
        if (_availableVoices.isNotEmpty && _selectedVoice == null) {
          _selectedVoice = _availableVoices.first;
        }
      }
    } catch (e) {
      debugPrint('Voice load error: $e');
    }
    notifyListeners();
  }

  Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoice = voice;
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
    notifyListeners();
    if (isPlaying && content != null) {
      await _tts.stop();
      await _tts.speak(content!);
    }
  }

  Future<void> _applyVoiceOrLocale(String locale) async {
    if (_selectedVoice != null) {
      await _tts.setVoice({
        'name': _selectedVoice!['name']!,
        'locale': _selectedVoice!['locale']!,
      });
    } else {
      await _tts.setLanguage(locale);
    }
  }

  Future<void> play(String t, String c, String locale) async {
    await _tts.stop();
    title = t;
    content = c;
    isPlaying = true;
    isVisible = true;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    sentenceStart = 0;
    sentenceEnd = 0;
    _currentCharOffset = 0;

    await _applyVoiceOrLocale(locale);
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(1.0);
    notifyListeners();
    await _tts.speak(c);
  }

  Future<void> togglePause(String locale) async {
    if (isPlaying) {
      await _tts.pause();
      isPlaying = false;
    } else {
      if (content != null) {
        await _applyVoiceOrLocale(locale);
        await _tts.speak(content!);
        isPlaying = true;
      }
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _tts.stop();
    isPlaying = false;
    isVisible = false;
    title = null;
    content = null;
    progress = 0.0;
    wordStart = 0;
    wordEnd = 0;
    sentenceStart = 0;
    sentenceEnd = 0;
    _currentCharOffset = 0;
    notifyListeners();
  }

  Future<void> setRate(double rate, String locale) async {
    speechRate = rate.clamp(0.1, 2.0);
    await _tts.setSpeechRate(speechRate);
    if (isPlaying && content != null) {
      await _tts.stop();
      await _applyVoiceOrLocale(locale);
      await _tts.speak(content!);
    }
    notifyListeners();
  }

  Future<void> restart(String locale) async {
    if (content != null) {
      await play(title ?? '', content!, locale);
    }
  }

  /// Seek forward by [seconds] — approximated by skipping characters.
  /// At ~150 wpm average, 1 second ≈ 12-15 chars. We use 13.
  Future<void> seekForward(int seconds, String locale) async {
    final text = content;
    if (text == null) return;
    final charsToSkip = (speechRate * 13 * seconds).round();
    int newOffset = (_currentCharOffset + charsToSkip).clamp(
      0,
      text.length - 1,
    );
    // Snap to next word boundary
    while (newOffset < text.length && text[newOffset] != ' ') newOffset++;
    newOffset = (newOffset + 1).clamp(0, text.length);
    final remaining = text.substring(newOffset);
    if (remaining.isEmpty) return;

    await _tts.stop();
    _currentCharOffset = newOffset;
    wordStart = newOffset;
    wordEnd = newOffset;
    progress = newOffset / text.length;
    await _applyVoiceOrLocale(locale);
    await _tts.speak(remaining);
    isPlaying = true;
    notifyListeners();
  }

  /// Seek backward by [seconds].
  Future<void> seekBackward(int seconds, String locale) async {
    final text = content;
    if (text == null) return;
    final charsToSkip = (speechRate * 13 * seconds).round();
    int newOffset = (_currentCharOffset - charsToSkip).clamp(
      0,
      text.length - 1,
    );
    // Snap back to previous word boundary
    while (newOffset > 0 && text[newOffset] != ' ') newOffset--;
    newOffset = (newOffset).clamp(0, text.length);
    final remaining = text.substring(newOffset);

    await _tts.stop();
    _currentCharOffset = newOffset;
    wordStart = newOffset;
    wordEnd = newOffset;
    progress = newOffset / text.length;
    await _applyVoiceOrLocale(locale);
    await _tts.speak(remaining);
    isPlaying = true;
    notifyListeners();
  }

  Future<void> showVoicePicker(BuildContext context) async {
    // Reload voices every time picker opens in case list was empty before
    if (_availableVoices.isEmpty) await _loadVoices();

    if (_availableVoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No voices found. Install more TTS voices in your device Settings → Accessibility → Text-to-Speech.',
          ),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (_, controller) => Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Select Voice',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${_availableVoices.length} voices available',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: _availableVoices.length,
                  itemBuilder: (_, i) {
                    final v = _availableVoices[i];
                    final isSelected = _selectedVoice?['name'] == v['name'];
                    // Make voice name more readable
                    final displayName = v['name']!
                        .replaceAll('-', ' ')
                        .replaceAll('_', ' ');
                    return Semantics(
                      label: 'Voice $displayName, locale ${v['locale']}',
                      selected: isSelected,
                      child: ListTile(
                        minVerticalPadding: 14,
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? const Color(0xFFD4B96A)
                              : Colors.grey[700],
                          radius: 18,
                          child: Text(
                            v['locale']!.substring(0, 2).toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          displayName,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFD4B96A)
                                : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          v['locale'] ?? '',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Color(0xFFD4B96A),
                              )
                            : null,
                        onTap: () {
                          setVoice(v);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
