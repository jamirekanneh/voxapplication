import 'dart:async';

import 'package:flutter/material.dart';

import 'headphone_audio_detector.dart';

/// Shared read-aloud UI shown above any route (overlay, not SnackBar).
class ReadAloudUi {
  ReadAloudUi._();

  static const _commandsList =
      'pause · play · continue · stop · forward · back';

  static String get voiceControlsIntro {
    if (HeadphoneAudioDetector.instance.isHeadphonesConnected) {
      return 'Earphones on — say $_commandsList while the app reads.';
    }
    return 'Voice while reading: $_commandsList. '
        'Plug in earphones if commands are missed.';
  }

  static String get voiceControlsPausedTip =>
      'Paused — say play, continue, stop, forward, or back.';

  static String get voiceControlsPlayingSpeakerTip =>
      'Say pause, stop, forward, or back. '
      'Earphones work best so the mic hears only you.';

  static String get voiceControlsPlayingHeadphoneTip =>
      'Say $_commandsList anytime while reading.';

  static final ValueNotifier<bool> voiceTipVisible = ValueNotifier(false);
  static final ValueNotifier<String> voiceTipMessage =
      ValueNotifier(voiceControlsIntro);

  static bool _voiceTipShown = false;
  static Timer? _hideTimer;

  static void resetVoiceTip() {
    _voiceTipShown = false;
    _hideTimer?.cancel();
    voiceTipVisible.value = false;
    voiceTipMessage.value = voiceControlsIntro;
  }

  static void showVoiceControlsTip() {
    if (_voiceTipShown) return;
    _voiceTipShown = true;

    _hideTimer?.cancel();
    voiceTipMessage.value = voiceControlsIntro;
    voiceTipVisible.value = true;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      voiceTipVisible.value = false;
    });
  }

  static void showVoiceEngineTip(String message) {
    if (message.isEmpty) return;
    _hideTimer?.cancel();
    voiceTipMessage.value = message;
    voiceTipVisible.value = true;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      voiceTipVisible.value = false;
    });
  }

  static void showFeedback(String message) {
    if (message.isEmpty) return;
    _hideTimer?.cancel();
    voiceTipMessage.value = message;
    voiceTipVisible.value = true;
    _hideTimer = Timer(const Duration(seconds: 2), () {
      voiceTipVisible.value = false;
      voiceTipMessage.value = voiceControlsIntro;
    });
  }
}

/// Floating banner for read-aloud voice tips and command feedback.
class ReadingVoiceTipBanner extends StatelessWidget {
  const ReadingVoiceTipBanner({
    super.key,
    required this.bottom,
    required this.message,
  });

  final double bottom;
  final String message;

  @override
  Widget build(BuildContext context) {
    final earphones = HeadphoneAudioDetector.instance.isHeadphonesConnected;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF141A29),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  earphones ? Icons.headphones_rounded : Icons.mic_none_rounded,
                  color: earphones ? const Color(0xFF4B9EFF) : Colors.grey[400],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
