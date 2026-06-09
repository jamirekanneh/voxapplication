import 'dart:async';

import 'package:flutter/material.dart';

import 'headphone_audio_detector.dart';

/// Shared read-aloud UI shown above any route (overlay, not SnackBar).
class ReadAloudUi {
  ReadAloudUi._();

  static String voiceControlsIntro(String Function(String) t) {
    if (HeadphoneAudioDetector.instance.isHeadphonesConnected) {
      return t('voice_controls_intro_headphones');
    }
    return t('voice_controls_intro_speaker');
  }

  static String voiceControlsPausedTip(String Function(String) t) =>
      t('voice_controls_paused_tip');

  static String voiceControlsPlayingSpeakerTip(String Function(String) t) =>
      t('voice_controls_playing_speaker_tip');

  static String voiceControlsPlayingHeadphoneTip(String Function(String) t) =>
      t('voice_controls_playing_headphone_tip');

  static final ValueNotifier<bool> voiceTipVisible = ValueNotifier(false);
  static final ValueNotifier<String> voiceTipMessage = ValueNotifier('');

  static bool _voiceTipShown = false;
  static Timer? _hideTimer;
  static String Function(String)? _defaultTranslator;

  static void configureTranslator(String Function(String) t) {
    _defaultTranslator = t;
    if (voiceTipMessage.value.isEmpty) {
      voiceTipMessage.value = voiceControlsIntro(t);
    }
  }

  static String Function(String) get _t =>
      _defaultTranslator ?? (k) => k;

  static String translate(String key) => _t(key);

  static void resetVoiceTip() {
    _voiceTipShown = false;
    _hideTimer?.cancel();
    voiceTipVisible.value = false;
    voiceTipMessage.value = voiceControlsIntro(_t);
  }

  static void showVoiceControlsTip([String Function(String)? t]) {
    if (_voiceTipShown) return;
    _voiceTipShown = true;
    final translate = t ?? _t;

    _hideTimer?.cancel();
    voiceTipMessage.value = voiceControlsIntro(translate);
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
      voiceTipMessage.value = voiceControlsIntro(_t);
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
