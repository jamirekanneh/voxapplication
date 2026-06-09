import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'reader_page.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  static Widget _miniIconButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = Colors.white70,
    double iconSize = 20,
  }) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, color: iconColor, size: iconSize),
        ),
      ),
    );
  }

  static Widget _miniPlayButton({
    required bool isPlaying,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: isPlaying ? 'Pause' : 'Play',
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(
            color: Color(0xFF4B9EFF),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: const Color(0xFF0A0E1A),
            size: 20,
          ),
        ),
      ),
    );
  }

  void _openReader(BuildContext context, TtsService tts, String locale) {
    if (tts.title == null || tts.content == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: tts),
            ChangeNotifierProvider.value(
              value: context.read<LanguageProvider>(),
            ),
          ],
          child: ReaderPage(
            title: tts.title!,
            content: tts.content!,
            locale: locale,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final locale =
        tts.readingLocale ?? context.watch<LanguageProvider>().ttsLocale;

    if (!tts.isVisible) return const SizedBox.shrink();

    return Semantics(
      label: 'Now reading: ${tts.title ?? ""}',
      child: Material(
        color: const Color(0xFF141A29),
        elevation: 6,
        shadowColor: const Color(0xFF0A0E1A).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: tts.progress,
              backgroundColor: Colors.grey[700],
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4B9EFF),
              ),
              minHeight: 3,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openReader(context, tts, locale),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openReader(context, tts, locale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tts.title ?? '',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${tts.speechRate.toStringAsFixed(2)}x speed',
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _miniIconButton(
                          label: 'Previous sentence',
                          icon: Icons.skip_previous,
                          onTap: () => tts.skipToAdjacentSentence(-1, locale),
                        ),
                        _miniPlayButton(
                          isPlaying: tts.isPlaying,
                          onTap: () => tts.togglePause(locale),
                        ),
                        _miniIconButton(
                          label: 'Next sentence',
                          icon: Icons.skip_next,
                          onTap: () => tts.skipToAdjacentSentence(1, locale),
                        ),
                        _miniIconButton(
                          label: 'Stop and close player',
                          icon: Icons.close,
                          iconColor: Colors.grey,
                          iconSize: 18,
                          onTap: () => tts.stop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
