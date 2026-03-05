import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tts_service.dart';
import 'language_provider.dart';
import 'reader_page.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = context.watch<TtsService>();
    final locale = context.watch<LanguageProvider>().ttsLocale;

    if (!tts.isVisible) return const SizedBox.shrink();

    return Semantics(
      label: 'Now reading: ${tts.title ?? ""}. Tap to open reader.',
      child: GestureDetector(
        onTap: () {
          if (tts.title != null && tts.content != null) {
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
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: LinearProgressIndicator(
                  value: tts.progress,
                  backgroundColor: Colors.grey[700],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFD4B96A),
                  ),
                  minHeight: 3,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tts.title ?? "",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "${tts.speechRate.toStringAsFixed(2)}x speed",
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: 'Decrease speed',
                      child: GestureDetector(
                        onTap: () => tts.setRate(tts.speechRate - 0.25, locale),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.remove_circle_outline,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      label: tts.isPlaying ? 'Pause' : 'Play',
                      child: GestureDetector(
                        onTap: () => tts.togglePause(locale),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD4B96A),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            tts.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      label: 'Increase speed',
                      child: GestureDetector(
                        onTap: () => tts.setRate(tts.speechRate + 0.25, locale),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.add_circle_outline,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      label: 'Stop and close player',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => tts.stop(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
