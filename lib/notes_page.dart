import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'language_provider.dart';
import 'temp_notes_provider.dart';
import 'tts_service.dart';
import 'ai_result_page.dart';
import 'theme_provider.dart';
import 'services/groq_service.dart';
import 'services/app_session.dart';
import 'services/auth_session.dart';
import 'widgets/firestore_data_gate.dart';
import 'services/mic_coordinator.dart';
import 'services/app_speech_service.dart';
import 'analytics_service.dart';
import 'services/saved_docs_service.dart';
import 'document_chat_buddy_sheet.dart';
import 'widgets/list_selection_bar.dart';

const int _kMaxTitleLength = 100;
const Duration _kMaxRecordingDuration = Duration(hours: 1);

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  RECORDING STATE ENUM
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
enum RecordingState { idle, recording, processing, done }

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with TickerProviderStateMixin {
  static const _dictationOwner = 'notes_dictation';
  static const _recordingSttOwner = 'notes_recording_stt';

  bool _isSaving = false;
  bool _isEditing = false;
  String? _editingId;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _transcriptController = TextEditingController();

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  RecordingState _recordingState = RecordingState.idle;
  bool _isPlaying = false;
  String? _audioPath;
  String? _audioUrl;
  Duration _audioDuration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  Timer? _maxDurationTimer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _peakRecordingDb = -160;
  bool _speechReadyForRecording = false;
  bool _recordingSttActive = false;
  String _recordingSttCommitted = '';
  String _recordingSttPartial = '';
  bool _isTitleDictating = false;
  bool _isTranscriptDictating = false;
  bool _isUploadingAudio = false;
  bool _isTranscribingAudio = false;
  String? _transcriptionError;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;

  String? _resolvedUid;
  bool _isAnonymousUser = false;
  final ScrollController _scrollController = ScrollController();

  // Multi-select mode
  bool _isNoteSelectionMode = false;
  final Set<String> _selectedNoteIds = {};
  List<String> _visibleNoteIds = [];

  Future<void> _releaseNotesMic() async {
    await AppSpeechService.instance.stop();
    _recordingSttActive = false;
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (_recordingState == RecordingState.recording) {
      await _audioRecorder.stop().catchError((_) => null);
    }
    if (mounted) {
      setState(() {
        _isTitleDictating = false;
        _isTranscriptDictating = false;
        if (_recordingState == RecordingState.recording) {
          _recordingState = RecordingState.idle;
        }
      });
    }
    MicCoordinator.instance.setNotesRecordingActive(false);
  }

  @override
  void initState() {
    super.initState();
    MicCoordinator.instance.registerReleaseHandler(_releaseNotesMic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MicCoordinator.instance.syncRouteIfCurrent(context, '/notes');
    });
    final bootUid = AppSession.bootstrapUid;
    if (bootUid != null) {
      _resolvedUid = bootUid;
      _isAnonymousUser = false;
    }
    _resolveUser();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MicCoordinator.instance.syncRouteIfCurrent(context, '/notes');
  }

  @override
  void dispose() {
    MicCoordinator.instance.unregisterReleaseHandler(_releaseNotesMic);
    MicCoordinator.instance.setNotesRecordingActive(false);
    AppSpeechService.instance.stop();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _titleController.dispose();
    _transcriptController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    _amplitudeSub?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  RESOLVE USER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _resolveUser() async {
    try {
      final session = await AuthSession.resolveForApp();
      if (!mounted) return;
      final nextGuest = session.guest;
      final nextUid = nextGuest ? null : (session.uid ?? _resolvedUid);
      if (nextGuest == _isAnonymousUser && nextUid == _resolvedUid) return;
      setState(() {
        _isAnonymousUser = nextGuest;
        _resolvedUid = nextUid;
      });
    } catch (e) {
      if (!mounted) return;
      final guest = await AuthSession.usesGuestExperience();
      if (guest == _isAnonymousUser && _resolvedUid == null) return;
      setState(() {
        _isAnonymousUser = guest;
        if (guest) _resolvedUid = null;
      });
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  MIC PERMISSION
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<bool> _requestMicPermission({bool forFileRecording = false}) async {
    final lang = context.read<LanguageProvider>();
    if (forFileRecording) {
      if (!MicCoordinator.instance.notesMayUseMic) return false;
      final ok =
          await MicCoordinator.instance.prepareForFileRecording(_audioRecorder);
      if (ok) return true;
      if (mounted) {
        final status = await Permission.microphone.status;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isPermanentlyDenied
                  ? lang.t('mic_blocked_settings')
                  : lang.t('mic_permission_required'),
            ),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
            action: status.isPermanentlyDenied
                ? SnackBarAction(
                    label: lang.t('settings'),
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
      }
      return false;
    }

    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('mic_denied_settings')),
          backgroundColor: VoxColors.surface(context),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: lang.t('settings'),
            textColor: VoxColors.primary(context),
            onPressed: openAppSettings,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('mic_permission_required')),
          backgroundColor: VoxColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  Future<void> _toggleDictation(bool isTitle) async {
    if (!mounted) return;
    if (_recordingState == RecordingState.recording) return;
    MicCoordinator.instance.syncRouteIfCurrent(context, '/notes');
    await MicCoordinator.instance.yieldFromAssistant();
    if (!MicCoordinator.instance.notesMayUseMic) {
      final lang = context.read<LanguageProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('voice_input_notes_only')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final langProvider = context.read<LanguageProvider>();
    final granted = await _requestMicPermission();
    if (!granted) return;

    if (isTitle ? _isTitleDictating : _isTranscriptDictating) {
      await AppSpeechService.instance.stop();
      setState(() {
        if (isTitle) {
          _isTitleDictating = false;
        } else {
          _isTranscriptDictating = false;
        }
      });
      return;
    }

    if (AppSpeechService.instance.isListening) {
      await AppSpeechService.instance.stop();
      setState(() {
        _isTitleDictating = false;
        _isTranscriptDictating = false;
      });
    }

    setState(() {
      if (isTitle) {
        _isTitleDictating = true;
      } else {
        _isTranscriptDictating = true;
      }
    });

    bool available = await AppSpeechService.instance.ensureInitialized(
      owner: _dictationOwner,
      onError: (e) {
        if (mounted) {
          setState(() {
            _isTitleDictating = false;
            _isTranscriptDictating = false;
          });
        }
      },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) {
            setState(() {
              _isTitleDictating = false;
              _isTranscriptDictating = false;
            });
          }
        }
      },
    );

    if (!available) {
      if (mounted) {
        setState(() {
          _isTitleDictating = false;
          _isTranscriptDictating = false;
        });
      }
      return;
    }

    if (!mounted) return;

    final String existingText = isTitle
        ? _titleController.text
        : _transcriptController.text;
    final prefix = existingText.isNotEmpty ? '$existingText ' : '';

    await AppSpeechService.instance.listen(
      owner: _dictationOwner,
      localeId: langProvider.sttLocale,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (val) {
        String newText = val.recognizedWords;
        // With partialResults: false, we just get the final chunk or we can use partial and just update.
        // It's better to update on the fly so it feels responsive.
        if (newText.isNotEmpty) {
          if (mounted) {
            setState(() {
              if (isTitle) {
                _titleController.text = '$prefix$newText';
                _titleController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _titleController.text.length),
                );
              } else {
                _transcriptController.text = '$prefix$newText';
                _transcriptController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _transcriptController.text.length),
                );
              }
            });
          }
        }
      },
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 3),
    );
  }

  String _combinedRecordingSttText() =>
      '$_recordingSttCommitted $_recordingSttPartial'.trim();

  bool _isSttTranscriptSufficient(String text, Duration duration) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final words =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final sec = duration.inSeconds;
    if (sec < 3) return words >= 1;
    if (sec < 15) return words >= 2;
    return words >= (sec / 4).ceil().clamp(2, 800);
  }

  Future<bool> _ensureSpeechReadyForRecording() async {
    if (_speechReadyForRecording) return true;
    _speechReadyForRecording = await AppSpeechService.instance.ensureInitialized(
      owner: _recordingSttOwner,
      onError: (e) {
        debugPrint('Recording STT error: $e');
        if (_recordingState == RecordingState.recording && mounted) {
          unawaited(_scheduleRecordingSttRestart());
        }
      },
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') &&
            _recordingState == RecordingState.recording &&
            mounted) {
          unawaited(_scheduleRecordingSttRestart());
        }
      },
    );
    return _speechReadyForRecording;
  }

  Future<void> _scheduleRecordingSttRestart() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _recordingState != RecordingState.recording) return;
    if (AppSpeechService.instance.isListening) return;
    await _startRecordingStt(context.read<LanguageProvider>());
  }

  Future<void> _startRecordingStt(LanguageProvider lang) async {
    if (_recordingState != RecordingState.recording) return;
    if (!MicCoordinator.instance.notesRecordingActive) return;

    final ready = await _ensureSpeechReadyForRecording();
    if (!ready || !mounted) return;
    if (_recordingState != RecordingState.recording) return;

    try {
      await AppSpeechService.instance.stop();
      if (_recordingState != RecordingState.recording) return;

      _recordingSttActive = true;
      await AppSpeechService.instance.listen(
        owner: _recordingSttOwner,
        localeId: lang.sttLocale,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: stt.ListenMode.dictation,
        ),
        onResult: (val) {
          final words = val.recognizedWords.trim();
          if (words.isEmpty || !mounted) return;
          setState(() {
            if (val.finalResult) {
              _recordingSttCommitted =
                  '$_recordingSttCommitted $words'.trim();
              _recordingSttPartial = '';
            } else {
              _recordingSttPartial = words;
            }
            final display = _combinedRecordingSttText();
            _transcriptController.text = display;
            _transcriptController.selection = TextSelection.fromPosition(
              TextPosition(offset: display.length),
            );
          });
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 6),
      );
    } catch (e) {
      debugPrint('Recording STT listen failed: $e');
      _recordingSttActive = false;
    }
  }

  Future<String> _stopRecordingStt() async {
    _recordingSttActive = false;
    try {
      await AppSpeechService.instance.stop();
    } catch (_) {}
    final text = _combinedRecordingSttText();
    _recordingSttCommitted = text;
    _recordingSttPartial = '';
    return text;
  }

  Future<void> _startRecording() async {
    MicCoordinator.instance.syncRouteIfCurrent(context, '/notes');
    await MicCoordinator.instance.yieldFromAssistant();

    // Pause read-aloud first so notes recording can take the mic.
    final tts = context.read<TtsService>();
    if (tts.isVisible && tts.isPlaying) {
      await tts.togglePause(context.read<LanguageProvider>().ttsLocale);
    }

    final rawTitle = _titleController.text.trim();
    if (rawTitle.isEmpty) {
      final lang = context.read<LanguageProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('title_before_record')),
          backgroundColor: VoxColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ),
      );
      try {
        unawaited(
          context.read<TtsService>().speakBrief(
                lang.t('title_before_record'),
                lang.ttsLocale,
              ),
        );
      } catch (_) {}
      return;
    }

    if (!MicCoordinator.instance.notesMayUseMic) {
      final lang = context.read<LanguageProvider>();
      final mic = MicCoordinator.instance;
      final message = mic.readAloudMicReserved
          ? 'Pause read-aloud before recording a voice note.'
          : mic.assistantMicActive
              ? 'Voice assistant is using the microphone. Tap record again or turn off the assistant.'
              : lang.t('recording_notes_only');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final granted = await _requestMicPermission(forFileRecording: true);
    if (!granted) return;

    MicCoordinator.instance.setNotesRecordingActive(true);

    try {
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      await AppSpeechService.instance.stop();

      _recordingSttCommitted = '';
      _recordingSttPartial = '';
      _transcriptController.clear();

      final dir = await getTemporaryDirectory();
      var encoder = AudioEncoder.wav;
      var ext = 'wav';
      if (!await _audioRecorder.isEncoderSupported(encoder)) {
        encoder = AudioEncoder.aacLc;
        ext = 'm4a';
        if (!await _audioRecorder.isEncoderSupported(encoder)) {
          throw Exception('This device does not support audio recording.');
        }
      }
      final fileName =
          'voice_note_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '${dir.path}/$fileName';

      _peakRecordingDb = -160;
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;

      final RecordConfig config = encoder == AudioEncoder.wav
          ? const RecordConfig(
              encoder: AudioEncoder.wav,
              numChannels: 1,
              sampleRate: 16000,
            )
          : RecordConfig(
              encoder: encoder,
              numChannels: 1,
              sampleRate: 16000,
              bitRate: 128000,
            );
      await _audioRecorder.start(config, path: path);
      if (!await _audioRecorder.isRecording()) {
        throw Exception(
          'Could not start audio recording. Check microphone permission in Settings.',
        );
      }

      _amplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen((amp) {
        if (amp.current > _peakRecordingDb) _peakRecordingDb = amp.current;
        if (amp.max > _peakRecordingDb) _peakRecordingDb = amp.max;
      });

      if (!mounted) return;
      setState(() {
        _audioPath = path;
        _audioUrl = null;
        _transcriptionError = null;
        _isUploadingAudio = false;
        _isTranscribingAudio = false;
        _recordingDuration = Duration.zero;
        _audioDuration = Duration.zero;
        _currentPosition = Duration.zero;
        _isPlaying = false;
        _recordingState = RecordingState.recording;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          final next = _recordingDuration + const Duration(seconds: 1);
          _recordingDuration =
              next > _kMaxRecordingDuration ? _kMaxRecordingDuration : next;
        });
      });

      _maxDurationTimer?.cancel();
      _maxDurationTimer = Timer(_kMaxRecordingDuration, () {
        if (mounted && _recordingState == RecordingState.recording) {
          _stopRecording();
        }
      });

      _transcriptController.clear();
    } catch (e) {
      MicCoordinator.instance.setNotesRecordingActive(false);
      debugPrint('Error starting recording: $e');
      _recordingTimer?.cancel();
      _maxDurationTimer?.cancel();
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;
      await _audioRecorder.stop().catchError((_) => null);
      if (mounted) {
        setState(() => _recordingState = RecordingState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await AppSpeechService.instance.stop();

    if (!mounted) {
      MicCoordinator.instance.setNotesRecordingActive(false);
      return;
    }
    setState(() => _recordingState = RecordingState.processing);

    try {
      String? actualPath = _audioPath;
      if (await _audioRecorder.isRecording()) {
        actualPath = await _audioRecorder.stop() ?? _audioPath;
      }

      if (actualPath == null || !await File(actualPath).exists()) {
        throw Exception(
          'No audio file was saved. Check microphone permission and try again.',
        );
      }

      _audioPath = actualPath;
      await _validateRecordingFile(actualPath, _recordingDuration);
      await _primeAudioPlayback(actualPath);

      if (_transcriptController.text.trim().isEmpty) {
        _transcriptController.text = '[Audio note - transcript pending]';
      }

      if (!mounted) return;
      setState(() {
        _recordingState = RecordingState.done;
        _transcriptionError = null;
      });

      unawaited(_syncRecordingToCloud(actualPath));
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      final errorText = e.toString().replaceFirst('Exception: ', '').trim();
      if (mounted) {
        setState(() {
          _isUploadingAudio = false;
          _isTranscribingAudio = false;
          _transcriptionError = errorText;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Recording processed, but upload/transcription failed: $errorText',
            ),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() {
        _recordingState = RecordingState.done;
      });
    } finally {
      MicCoordinator.instance.setNotesRecordingActive(false);
    }
  }

  Future<String> _uploadAudioNow(String localPath) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('Please sign in with your account to upload recordings.');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw Exception('Audio file not found.');
    }
    await GroqService.ensureLocalAudioReady(localPath);
    final ext = localPath.toLowerCase().endsWith('.wav') ? 'wav' : 'm4a';
    final contentType = ext == 'wav' ? 'audio/wav' : 'audio/m4a';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance
        .ref()
        .child('recordings')
        .child(user.uid)
        .child(fileName);
    try {
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      final snapshot = await uploadTask.whenComplete(() {});
      return snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized') {
        throw Exception(
          'Upload blocked by Firebase Storage rules. Ensure recordings/${user.uid}/... is allowed for the signed-in UID.',
        );
      }
      if (e.code == 'object-not-found') {
        throw Exception('Storage path not found. Check Firebase bucket/path configuration.');
      }
      rethrow;
    }
  }

  Future<void> _primeAudioPlayback(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(localPath);
      var duration = _audioPlayer.duration;
      if (duration == null || duration <= Duration.zero) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        duration = _audioPlayer.duration;
      }
      if (!mounted) return;
      setState(() {
        _audioDuration = (duration != null && duration > Duration.zero)
            ? duration
            : _recordingDuration;
        _currentPosition = Duration.zero;
        _isPlaying = false;
      });
    } catch (e) {
      debugPrint('Prime playback failed: $e');
      if (mounted) {
        setState(() {
          _audioDuration = _recordingDuration;
          _currentPosition = Duration.zero;
          _isPlaying = false;
        });
      }
    }
  }

  Future<void> _validateRecordingFile(String path, Duration duration) async {
    await GroqService.ensureLocalAudioReady(path);
    final size = await File(path).length();
    if (duration.inSeconds >= 3 && size < duration.inSeconds * 1200) {
      throw Exception(
        'Recording file is too small. The microphone may not have captured audio.',
      );
    }
    if (duration.inSeconds >= 2 && _peakRecordingDb < -45) {
      throw Exception(
        'No voice detected. Allow microphone access and try again.',
      );
    }
  }

  Future<void> _syncRecordingToCloud(String localPath) async {
    if (!mounted) return;
    final lang = context.read<LanguageProvider>();
    final authUser = FirebaseAuth.instance.currentUser;
    final canUpload = authUser != null && !authUser.isAnonymous;

    try {
      if (canUpload) {
        if (mounted) {
          setState(() {
            _transcriptionError = null;
            _isUploadingAudio = true;
            _isTranscribingAudio = false;
          });
        }
        final downloadUrl = await _uploadAudioNow(localPath);
        if (!mounted) return;
        setState(() {
          _audioUrl = downloadUrl;
          _isUploadingAudio = false;
          _isTranscribingAudio = true;
        });
      }

      if (mounted) {
        setState(() => _isTranscribingAudio = true);
      }
      final transcript = (await GroqService.transcribeLocalFile(
        localPath,
        expectedDuration: _recordingDuration,
      )).trim();

      if (!mounted) return;
      setState(() {
        _isTranscribingAudio = false;
        if (transcript.isNotEmpty) {
          _transcriptController.text = transcript;
          _transcriptionError = null;
        } else {
          _transcriptionError = 'Transcript could not be generated.';
        }
      });

      if (canUpload && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              transcript.isNotEmpty
                  ? lang.t('transcription_complete')
                  : 'Audio saved. Transcript could not be generated.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Cloud sync failed: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _isUploadingAudio = false;
        _isTranscribingAudio = false;
        _transcriptionError = canUpload ? msg : null;
      });
      if (canUpload) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload/transcription: $msg'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _discardRecording() {
    MicCoordinator.instance.setNotesRecordingActive(false);
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingSttCommitted = '';
    _recordingSttPartial = '';
    _recordingSttActive = false;
    AppSpeechService.instance.stop();
    _audioRecorder.stop();
    setState(() {
      _recordingState = RecordingState.idle;
      _audioPath = null;
      _audioUrl = null;
      _isUploadingAudio = false;
      _isTranscribingAudio = false;
      _transcriptionError = null;
      _recordingDuration = Duration.zero;
      _audioDuration = Duration.zero;
      _currentPosition = Duration.zero;
      _isPlaying = false;
      _transcriptController.clear();
    });
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  PLAYBACK
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _playAudio({String? url, String? localPath}) async {
    final targetUrl = url ?? _audioUrl;
    final targetPath = localPath ?? _audioPath;
    if ((targetUrl == null || targetUrl.isEmpty) &&
        (targetPath == null || targetPath.isEmpty)) {
      return;
    }

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        if (mounted) setState(() => _isPlaying = false);
        return;
      }

      if (targetUrl != null && targetUrl.isNotEmpty) {
        await _audioPlayer.setUrl(targetUrl);
      } else {
        final file = File(targetPath!);
        if (!await file.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Audio file is no longer available on this device.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        await _audioPlayer.setFilePath(targetPath);
      }

      _audioPlayer.positionStream.listen((p) {
        if (mounted) setState(() => _currentPosition = p);
      });
      _audioPlayer.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _audioDuration = d);
      });
      _audioPlayer.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed && mounted) {
          setState(() {
            _isPlaying = false;
            _currentPosition = Duration.zero;
          });
        }
      });
      await _audioPlayer.play();
      if (mounted) setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('Error playing audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not play audio: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  SAVE NOTE
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _defaultRecordingTitle() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final m = now.minute.toString().padLeft(2, '0');
    return 'Recording ${now.month}/${now.day} $h:$m $ampm';
  }

  Future<void> _saveNote(LanguageProvider lang) async {
    final transcript = _transcriptController.text.trim();
    var rawTitle = _titleController.text.trim();
    final hasAudio = (_audioUrl?.isNotEmpty ?? false) ||
        (_audioPath != null && _audioPath!.isNotEmpty);
    final hasTranscript = transcript.isNotEmpty;
    if (rawTitle.isEmpty && hasAudio) {
      rawTitle = _defaultRecordingTitle();
      _titleController.text = rawTitle;
    }
    final title = rawTitle.isNotEmpty ? rawTitle : 'Note';
    final contentToSave = hasTranscript
        ? transcript
        : (hasAudio ? '[Audio note - transcript pending]' : '');

    if (rawTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('title_before_save')),
          backgroundColor: VoxColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ),
      );
      return;
    }
    if (!hasTranscript && !hasAudio) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('record_before_save')),
          backgroundColor: VoxColors.danger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      if (_isEditing && _editingId != null) {
        if (_isAnonymousUser) {
          context.read<TempNotesProvider>().update(
            _editingId!,
            title,
            contentToSave,
            audioUrl: _audioUrl,
            audioPath: _audioPath,
            durationSeconds: _recordingDuration.inSeconds,
          );
        } else {
          await FirebaseFirestore.instance
              .collection('notes')
              .doc(_editingId)
              .update({
                'title': title,
                'content': contentToSave,
                'audioUrl': _audioUrl,
                'recordingDurationSeconds': _recordingDuration.inSeconds,
                'lastUpdated': FieldValue.serverTimestamp(),
              });
        }
      } else {
        if (_isAnonymousUser) {
          context.read<TempNotesProvider>().add(
            title,
            contentToSave,
            audioUrl: _audioUrl,
            audioPath: _audioPath,
            durationSeconds: _recordingDuration.inSeconds,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(lang.t('guest_note_saved')),
                backgroundColor: VoxColors.surface(context),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
              ),
            );
          }
        } else {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null || user.isAnonymous) {
            throw Exception('Please sign in to save notes to your account.');
          }
          final docRef =
              await FirebaseFirestore.instance.collection('notes').add({
            'userId': user.uid,
            'title': title,
            'content': contentToSave,
            'audioUrl': _audioUrl,
            'recordingDurationSeconds': _recordingDuration.inSeconds,
            'timestamp': FieldValue.serverTimestamp(),
          });
          if (GroqService.isTranscriptPending(contentToSave) &&
              (_audioUrl?.isNotEmpty ?? false)) {
            unawaited(
              _transcribeExistingNote(
                docId: docRef.id,
                audioUrl: _audioUrl!,
                localPath: _audioPath,
                durationSeconds: _recordingDuration.inSeconds,
                silent: true,
              ),
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(lang.t('note_saved')),
                behavior: SnackBarBehavior.floating,
                backgroundColor: VoxColors.surface(context),
                margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
              ),
            );
          }
        }
      }

      unawaited(AnalyticsService.instance.recordNoteSaved());
      if (!_isAnonymousUser) {
        unawaited(AnalyticsService.instance.syncToFirebase());
      }

      if (mounted) {
        setState(() {
          _titleController.clear();
          _transcriptController.clear();
          _isEditing = false;
          _editingId = null;
          _audioPath = null;
          _audioUrl = null;
          _isUploadingAudio = false;
          _isTranscribingAudio = false;
          _transcriptionError = null;
          _recordingState = RecordingState.idle;
          _recordingDuration = Duration.zero;
          _audioDuration = Duration.zero;
          _currentPosition = Duration.zero;
          _isPlaying = false;
        });
        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
        await _resolveUser();
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'unavailable'
                  ? 'No internet. Note will sync when back online.'
                  : '${lang.t('error_saving')} ${e.message}',
            ),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${lang.t('error_saving')} $e'),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ————————————————————————————————————————————————
  //  DELETE
  // ————————————————————————————————————————————————
  Future<void> _deleteNote(String docId) async {
    final lang = context.read<LanguageProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VoxColors.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: VoxColors.border(context)),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: VoxColors.danger),
            const SizedBox(width: 8),
            Text(lang.t('delete_note_title'),
                style: TextStyle(color: VoxColors.onSurface(context))),
          ],
        ),
        content: Text(
          lang.t('delete_note_body'),
          style: TextStyle(color: VoxColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              lang.t('cancel'),
              style: const TextStyle(color: Color(0x8A0A0E1A)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: VoxColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(lang.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final docRef = FirebaseFirestore.instance.collection('notes').doc(docId);
      final snapshot = await docRef.get();
      String? noteTitle;
      if (snapshot.exists) {
        final data = snapshot.data()!;
        noteTitle = data['title']?.toString();
        final targetUid =
            data['userId']?.toString() ??
            FirebaseAuth.instance.currentUser?.uid ??
            _resolvedUid;
        if (targetUid != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(targetUid)
              .collection('deleted_library')
              .add({
                'fileName': data['title'] ?? 'Note',
                'content': data['content'],
                'audioUrl': data['audioUrl'],
                'recordingDurationSeconds': data['recordingDurationSeconds'],
                'fileType': 'note',
                'sourceCollection': 'notes',
                'deletedAt': FieldValue.serverTimestamp(),
                'originalTimestamp':
                    data['timestamp'] ?? FieldValue.serverTimestamp(),
                'userId': data['userId'] ?? targetUid,
              });
        }
      }
      await docRef.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.delete_sweep_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    noteTitle != null
                        ? lang.tNamed('note_moved_recycle_named', {
                            'title': noteTitle,
                          })
                        : lang.t('note_moved_recycle'),
                  ),
                ),
              ],
            ),
            backgroundColor: VoxColors.surface(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'unavailable'
                  ? lang.t('cannot_delete_offline')
                  : '${lang.t('delete_failed')} ${e.message}',
            ),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _deleteTempNote(String id, TempNotesProvider tempNotes) {
    tempNotes.remove(id);
    if (_isEditing && _editingId == id) _cancelEdit();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.read<LanguageProvider>().t('note_deleted')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: VoxColors.surface(context),
        margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
      ),
    );
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editingId = null;
      _titleController.clear();
      _transcriptController.clear();
      _recordingState = RecordingState.idle;
      _audioPath = null;
      _audioUrl = null;
      _recordingDuration = Duration.zero;
    });
  }

  // ————————————————————————————————————————————————
  //  SELECTION MODE HELPERS
  // ————————————————————————————————————————————————
  void _enterNoteSelectionMode(String id) {
    setState(() {
      _isNoteSelectionMode = true;
      _selectedNoteIds.clear();
      _selectedNoteIds.add(id);
    });
  }

  void _exitNoteSelectionMode() {
    setState(() {
      _isNoteSelectionMode = false;
      _selectedNoteIds.clear();
    });
  }

  void _toggleNoteSelection(String id) {
    setState(() {
      if (_selectedNoteIds.contains(id)) {
        _selectedNoteIds.remove(id);
        if (_selectedNoteIds.isEmpty) _isNoteSelectionMode = false;
      } else {
        _selectedNoteIds.add(id);
      }
    });
  }

  void _toggleSelectAllNotes() {
    setState(() {
      if (_selectedNoteIds.length == _visibleNoteIds.length &&
          _visibleNoteIds.isNotEmpty) {
        _selectedNoteIds.clear();
      } else {
        _selectedNoteIds.addAll(_visibleNoteIds);
      }
    });
  }

  // ————————————————————————————————————————————————
  //  DELETE SELECTED NOTES
  // ————————————————————————————————————————————————
  Future<void> _deleteSelectedNotes() async {
    if (_selectedNoteIds.isEmpty) return;
    final lang = context.read<LanguageProvider>();
    final count = _selectedNoteIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VoxColors.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: VoxColors.border(context)),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: VoxColors.danger),
            const SizedBox(width: 8),
            Text(lang.t('delete_selected_title'),
                style: TextStyle(color: VoxColors.onSurface(context))),
          ],
        ),
        content: Text(
          lang.t('delete_note_body'),
          style: TextStyle(color: VoxColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              lang.t('cancel'),
              style: const TextStyle(color: Color(0x8A0A0E1A)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: VoxColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(lang.tNamed('delete_notes_count', {'count': '$count'})),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      if (_isAnonymousUser) {
        final provider = context.read<TempNotesProvider>();
        for (var id in _selectedNoteIds.toList()) {
          provider.remove(id);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                lang.tNamed('notes_deleted_count', {'count': '$count'}),
              ),
              backgroundColor: const Color(0xFF333333),
            ),
          );
        }
      } else {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? _resolvedUid;
        if (uid == null) return;

        final batch = FirebaseFirestore.instance.batch();
        final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

        for (var docId in _selectedNoteIds) {
          final docRef = FirebaseFirestore.instance
              .collection('notes')
              .doc(docId);
          final snapshot = await docRef.get();
          if (snapshot.exists) {
            final data = snapshot.data()!;
            final newDocRef = userDoc.collection('deleted_library').doc();
            batch.set(newDocRef, {
              'fileName': data['title'] ?? 'Note',
              'content': data['content'],
              'audioUrl': data['audioUrl'],
              'recordingDurationSeconds': data['recordingDurationSeconds'],
              'fileType': 'note',
              'sourceCollection': 'notes',
              'deletedAt': FieldValue.serverTimestamp(),
              'originalTimestamp':
                  data['timestamp'] ?? FieldValue.serverTimestamp(),
              'userId': uid,
            });
            batch.delete(docRef);
          }
        }
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                lang.tNamed('notes_moved_recycle_count', {'count': '$count'}),
              ),
              backgroundColor: VoxColors.surface(context),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${lang.t('failed_to_delete')} $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }

    _exitNoteSelectionMode();
  }

  // Search Bar at top of notes list
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Future<void> _transcribeExistingNote({
    required String docId,
    required String audioUrl,
    String? localPath,
    int? durationSeconds,
    bool silent = false,
  }) async {
    if (_isAnonymousUser) return;
    try {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<LanguageProvider>().t('transcribing_audio')),
            backgroundColor: VoxColors.surface(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      final transcript = (localPath != null && localPath.isNotEmpty)
          ? await GroqService.transcribeLocalFile(
              localPath,
              expectedDuration: durationSeconds != null
                  ? Duration(seconds: durationSeconds)
                  : null,
            )
          : await GroqService.transcribeAudio(
              audioUrl,
              expectedDuration: durationSeconds != null
                  ? Duration(seconds: durationSeconds)
                  : null,
            );
      await FirebaseFirestore.instance.collection('notes').doc(docId).update({
        'content': transcript.trim().isEmpty
            ? '[No speech detected in recording]'
            : transcript.trim(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<LanguageProvider>().t('transcript_updated')),
            backgroundColor: VoxColors.surface(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.read<LanguageProvider>().t('transcription_failed')} $e',
            ),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateNoteTranscript(String docId, String transcript) async {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) {
      throw Exception(context.read<LanguageProvider>().t('transcript_empty'));
    }

    if (_isAnonymousUser) {
      final temp = context.read<TempNotesProvider>();
      final matches = temp.notes.where((n) => n.id == docId);
      if (matches.isEmpty) {
        throw Exception(context.read<LanguageProvider>().t('note_not_found'));
      }
      final existing = matches.first;
      temp.update(
        docId,
        existing.title,
        cleaned,
        audioUrl: existing.audioUrl,
        audioPath: existing.audioPath,
        durationSeconds: existing.durationSeconds,
      );
      return;
    }

    await FirebaseFirestore.instance.collection('notes').doc(docId).update({
      'content': cleaned,
      'pendingTranscript': cleaned,
      'transcriptStatus': 'done',
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  bool _canSaveTranscriptToDocs(String content) {
    final cleaned = content.trim();
    return cleaned.isNotEmpty && !GroqService.isTranscriptPending(cleaned);
  }

  String _editorNoteTitle() {
    final raw = _titleController.text.trim();
    if (raw.isNotEmpty) return raw;
    if (_recordingState == RecordingState.done) {
      return _defaultRecordingTitle();
    }
    return 'Note';
  }

  Future<void> _saveCurrentEditorToSavedDocs(LanguageProvider lang) async {
    await _saveNoteToSavedDocs(
      _editingId ?? '',
      _editorNoteTitle(),
      _transcriptController.text,
    );
  }

  void _openChatBuddy(String title, String content) {
    DocumentChatBuddySheet.show(
      context,
      documentTitle: title,
      documentContent: content,
    );
  }

  Future<void> _saveNoteToSavedDocs(
    String noteId,
    String title,
    String content,
  ) async {
    if (_isAnonymousUser) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LanguageProvider>().t('saved_docs_sign_in_hint'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final cleaned = content.trim();
    if (cleaned.isEmpty ||
        GroqService.isTranscriptPending(cleaned)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<LanguageProvider>().t('save_note_need_transcript'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final lang = context.read<LanguageProvider>();
    final saveTitle = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: title);
        return AlertDialog(
          title: Text(lang.t('save_to_saved_docs')),
          content: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: lang.t('note_title_field_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(lang.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(lang.t('save_note')),
            ),
          ],
        );
      },
    );
    if (saveTitle == null || saveTitle.isEmpty) return;

    try {
      await SavedDocsService.saveNote(
        title: saveTitle,
        content: cleaned,
        source: 'Notes',
        noteId: noteId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.t('saved_to_saved_docs')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${lang.t('error_saving')} $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _downloadTranscript(String title, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/${title}_$timestamp.txt');
    await file.writeAsString(content);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.read<LanguageProvider>().tNamed('transcript_saved_to', {
            'path': file.path,
          }),
        ),
      ),
    );
  }

  // ————————————————————————————————————————————————
  //  NOTE DETAIL BOTTOM SHEET
  // ————————————————————————————————————————————————
  void _showNoteDetails(
    String id,
    String title,
    String content, {
    String? audioUrl,
    String? audioPath,
    int? durationSeconds,
  }) {
    final lang = context.read<LanguageProvider>();
    final tts = context.read<TtsService>();
    final sheetTranscriptController = TextEditingController(text: content);
    bool isSpeaking = false;
    String sheetContent = content;
    bool isEditingTranscript = false;
    bool isUpdatingTranscript = false;
    final hasPlayableAudio =
        (audioUrl?.isNotEmpty ?? false) || (audioPath?.isNotEmpty ?? false);
    int activeTab = hasPlayableAudio ? 1 : 0;
    final AudioPlayer localPlayer = AudioPlayer();
    bool isPlayingLocal = false;
    Duration localPos = Duration.zero;
    Duration localDur = Duration.zero;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        if (!_isAnonymousUser &&
            hasPlayableAudio &&
            GroqService.isTranscriptPending(content) &&
            audioUrl != null &&
            audioUrl.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _transcribeExistingNote(
              docId: id,
              audioUrl: audioUrl,
              durationSeconds: durationSeconds,
              silent: true,
            );
          });
        }

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F4FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: DraggableScrollableSheet(
                  initialChildSize: 0.88,
                  minChildSize: 0.5,
                  maxChildSize: 0.97,
                  expand: false,
                  builder: (_, scrollController) => Column(
                    children: [
                      // Handle
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Color(0x420A0E1A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            _sheetIconBtn(
                              icon: isSpeaking
                                  ? Icons.stop_circle_outlined
                                  : Icons.volume_up_rounded,
                              color: isSpeaking
                                  ? const Color(0xFF4B9EFF)
                                  : Color(0x8A0A0E1A),
                              onTap: () async {
                                if (sheetContent.trim().isEmpty) return;
                                if (isSpeaking) {
                                  await tts.togglePause(lang.ttsLocale);
                                  setSheetState(() => isSpeaking = false);
                                } else {
                                  localPlayer.stop();
                                  _audioPlayer.stop();
                                  await tts.play(
                                    title,
                                    sheetContent,
                                    lang.ttsLocale,
                                  );
                                  setSheetState(() => isSpeaking = true);
                                }
                              },
                            ),
                            _sheetIconBtn(
                              icon: Icons.file_download_outlined,
                              color: Color(0x8A0A0E1A),
                              onTap: () =>
                                  _downloadTranscript(title, sheetContent),
                            ),
                            _sheetIconBtn(
                              icon: Icons.bookmark_add_outlined,
                              color: const Color(0xFF4B9EFF),
                              onTap: () => _saveNoteToSavedDocs(
                                id,
                                title,
                                sheetContent,
                              ),
                            ),
                            if (audioUrl != null &&
                                GroqService.isTranscriptPending(sheetContent))
                              _sheetIconBtn(
                                icon: Icons.transcribe_outlined,
                                color: const Color(0xFF4B9EFF),
                                onTap: () async {
                                  await _transcribeExistingNote(
                                    docId: id,
                                    audioUrl: audioUrl,
                                    durationSeconds: durationSeconds,
                                  );
                                },
                              ),
                            _sheetIconBtn(
                              icon: isEditingTranscript
                                  ? Icons.close
                                  : Icons.edit_note_rounded,
                              color: isEditingTranscript
                                  ? const Color(0xFF4B9EFF)
                                  : Color(0x8A0A0E1A),
                              onTap: () async {
                                if (isSpeaking) {
                                  await tts.togglePause(lang.ttsLocale);
                                  setSheetState(() => isSpeaking = false);
                                }
                                setSheetState(() {
                                  isEditingTranscript = !isEditingTranscript;
                                  sheetTranscriptController.text = sheetContent;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 4),
                      if (durationSeconds != null && durationSeconds > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, bottom: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(
                                  Duration(seconds: durationSeconds),
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // â”€â”€ AI Tools bar â”€â”€
                      if (sheetContent.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Color(0xFF0A0E1A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome,
                                      size: 13,
                                      color: Color(0xFF4B9EFF),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      lang.t('ai_tools'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: Color(0xFF4B9EFF),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _aiChip(
                                    label: lang.t('summarize'),
                                    icon: Icons.summarize_outlined,
                                    dark: true,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AiResultPage(
                                            documentTitle: title,
                                            documentContent: sheetContent,
                                            mode: 'summary',
                                            source: 'Notes',
                                            outputLanguage: lang.selectedLanguage,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _aiChip(
                                    label: lang.t('qa_generator'),
                                    icon: Icons.style_outlined,
                                    dark: false,
                                    onTap: () async {
                                      final nav = Navigator.of(context);
                                      final count =
                                          await _pickCardCount(context);
                                      if (count == null) return;
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      if (!context.mounted) return;
                                      nav.push(
                                        MaterialPageRoute(
                                          builder: (_) => AiResultPage(
                                            documentTitle: title,
                                            documentContent: sheetContent,
                                            mode: 'flashcards',
                                            cardCount: count,
                                            source: 'Notes',
                                            outputLanguage: lang.selectedLanguage,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _aiChip(
                                    label: lang.t('study_buddy'),
                                    icon: Icons.psychology,
                                    dark: true,
                                    onTap: () async {
                                      if (isSpeaking) {
                                        await tts.togglePause(lang.ttsLocale);
                                        setSheetState(() => isSpeaking = false);
                                      }
                                      localPlayer.stop();
                                      _audioPlayer.stop();
                                      _openChatBuddy(title, sheetContent);
                                    },
                                  ),
                                ],
                              ),
                            ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // â”€â”€ Tabs â”€â”€
                      if ((audioUrl?.isNotEmpty ?? false) ||
                          (audioPath?.isNotEmpty ?? false)) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              _tabChip(
                                label: lang.t('tab_transcript'),
                                selected: activeTab == 0,
                                onTap: () => setSheetState(() => activeTab = 0),
                              ),
                              const SizedBox(width: 8),
                              _tabChip(
                                label: lang.t('tab_audio'),
                                selected: activeTab == 1,
                                onTap: () => setSheetState(() => activeTab = 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 20,
                        endIndent: 20,
                      ),

                      // â”€â”€ Body â”€â”€
                      Expanded(
                        child: activeTab == 0
                            ? ListView(
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  40,
                                ),
                                children: [
                                  if (sheetContent.trim().isNotEmpty) ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _transcriptActionChip(
                                          label: isEditingTranscript
                                              ? lang.t('cancel')
                                              : lang.t('edit'),
                                          icon: isEditingTranscript
                                              ? Icons.close
                                              : Icons.edit_note,
                                          onTap: () async {
                                            if (isSpeaking) {
                                              await tts.togglePause(
                                                lang.ttsLocale,
                                              );
                                            }
                                            setSheetState(() {
                                              isSpeaking = false;
                                              isEditingTranscript =
                                                  !isEditingTranscript;
                                              sheetTranscriptController.text =
                                                  sheetContent;
                                            });
                                          },
                                        ),
                                        if (isEditingTranscript)
                                          _transcriptActionChip(
                                            label: isUpdatingTranscript
                                                ? lang.t('updating')
                                                : lang.t('update'),
                                            icon: Icons.check,
                                            onTap: isUpdatingTranscript
                                                ? null
                                                : () async {
                                                    final next =
                                                        sheetTranscriptController
                                                            .text
                                                            .trim();
                                                    if (next.isEmpty) {
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            lang.t('transcript_empty'),
                                                          ),
                                                          backgroundColor:
                                                              VoxColors.danger,
                                                          behavior:
                                                              SnackBarBehavior
                                                                  .floating,
                                                        ),
                                                      );
                                                      return;
                                                    }
                                                    setSheetState(() {
                                                      isUpdatingTranscript =
                                                          true;
                                                    });
                                                    try {
                                                      await _updateNoteTranscript(
                                                        id,
                                                        next,
                                                      );
                                                      setSheetState(() {
                                                        sheetContent = next;
                                                        isEditingTranscript =
                                                            false;
                                                        isUpdatingTranscript =
                                                            false;
                                                      });
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              lang.t('transcript_updated'),
                                                            ),
                                                            backgroundColor:
                                                                VoxColors
                                                                    .surface(
                                                              context,
                                                            ),
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      setSheetState(() {
                                                        isUpdatingTranscript =
                                                            false;
                                                      });
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              '${lang.t('update_failed')} $e',
                                                            ),
                                                            backgroundColor:
                                                                VoxColors
                                                                    .danger,
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  if (isEditingTranscript)
                                    TextField(
                                      controller: sheetTranscriptController,
                                      maxLines: null,
                                      minLines: 8,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.65,
                                        color: Color(0xDD0A0E1A),
                                      ),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.white,
                                        hintText: lang.t('transcript_edit_hint'),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      sheetContent.trim().isEmpty
                                          ? lang.t('no_transcript_yet')
                                          : sheetContent,
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.75,
                                        color: sheetContent.trim().isEmpty
                                            ? Color(0x8A0A0E1A)
                                            : Color(0xDD0A0E1A),
                                      ),
                                    ),
                                ],
                              )
                            : _audioPlayerPanel(
                                audioUrl: audioUrl,
                                audioPath: audioPath,
                                beforePlay: () async {
                                  if (isSpeaking) {
                                    await tts.togglePause(lang.ttsLocale);
                                    if (ctx.mounted) {
                                      setSheetState(() => isSpeaking = false);
                                    }
                                  }
                                  await _audioPlayer.stop();
                                },
                                isPlayingLocal: isPlayingLocal,
                                localPos: localPos,
                                localDur: localDur,
                                localPlayer: localPlayer,
                                onStateChanged: (playing, pos, dur) {
                                  setSheetState(() {
                                    isPlayingLocal = playing;
                                    localPos = pos;
                                    localDur = dur;
                                  });
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() async {
      if (isSpeaking) {
        await tts.togglePause(lang.ttsLocale);
      }
      localPlayer.stop();
      localPlayer.dispose();
      sheetTranscriptController.dispose();
    });
  }

  Widget _transcriptActionChip({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 15, color: const Color(0xFF4B9EFF)),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white,
      disabledColor: Colors.white.withValues(alpha: 0.65),
      labelStyle: const TextStyle(
        color: Color(0xFF0A0E1A),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(color: Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  Widget _audioPlayerPanel({
    String? audioUrl,
    String? audioPath,
    required Future<void> Function() beforePlay,
    required bool isPlayingLocal,
    required Duration localPos,
    required Duration localDur,
    required AudioPlayer localPlayer,
    required void Function(bool playing, Duration pos, Duration dur)
    onStateChanged,
  }) {
    final lang = context.read<LanguageProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Color(0xFF0A0E1A),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic, color: const Color(0xFF4B9EFF), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      lang.t('voice_recording'),
                      style: TextStyle(
                        color: Color(0xFF4B9EFF),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    try {
                      if (isPlayingLocal) {
                        await localPlayer.pause();
                        onStateChanged(false, localPos, localDur);
                        return;
                      }
                      await beforePlay();
                      if (audioUrl != null && audioUrl.isNotEmpty) {
                        await localPlayer.setUrl(audioUrl);
                      } else if (audioPath != null && audioPath.isNotEmpty) {
                        final file = File(audioPath);
                        if (!await file.exists()) {
                          throw Exception(
                            lang.t('audio_gone_device'),
                          );
                        }
                        await localPlayer.setFilePath(audioPath);
                      } else {
                        throw Exception(lang.t('no_audio_for_note'));
                      }
                      localPlayer.positionStream.listen(
                        (p) => onStateChanged(true, p, localDur),
                      );
                      localPlayer.durationStream.listen((d) {
                        if (d != null) onStateChanged(true, localPos, d);
                      });
                      localPlayer.playerStateStream.listen((s) {
                        if (s.processingState == ProcessingState.completed) {
                          onStateChanged(false, Duration.zero, localDur);
                        }
                      });
                      await localPlayer.play();
                      onStateChanged(true, localPos, localDur);
                    } catch (e) {
                      debugPrint('Playback error: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${lang.t('could_not_play_audio')} $e'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B9EFF),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: Icon(
                      isPlayingLocal
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Color(0xFF0A0E1A),
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (localDur > Duration.zero) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(localPos),
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatDuration(localDur),
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF4B9EFF),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF4B9EFF),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: localPos.inSeconds.toDouble().clamp(
                        0,
                        localDur.inSeconds.toDouble(),
                      ),
                      max: localDur.inSeconds.toDouble(),
                      onChanged: (v) =>
                          localPlayer.seek(Duration(seconds: v.toInt())),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetIconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _aiChip({
    required String label,
    required IconData icon,
    required bool dark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFF4B9EFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: dark ? const Color(0xFF4B9EFF) : Color(0xFF0A0E1A),
              size: 12,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: dark ? const Color(0xFF4B9EFF) : Color(0xFF0A0E1A),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Color(0xFF0A0E1A)
              : Color(0xFF0A0E1A).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF4B9EFF) : Color(0x8A0A0E1A),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<int?> _pickCardCount(BuildContext context) async {
    final lang = context.read<LanguageProvider>();
    int selected = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF0F4FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            lang.t('how_many_questions'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                lang.tNamed('cards_count', {'count': '$selected'}),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4B9EFF),
                ),
              ),
              Slider(
                value: selected.toDouble(),
                min: 5,
                max: 20,
                divisions: 15,
                activeColor: Color(0xFF0A0E1A),
                inactiveColor: Colors.grey[300],
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '5',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '20',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                lang.t('cancel'),
                style: const TextStyle(color: Color(0x8A0A0E1A)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF0A0E1A),
                foregroundColor: const Color(0xFF4B9EFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(lang.t('generate')),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  RECORDING AREA WIDGET
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildRecordingArea(LanguageProvider lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recordingState == RecordingState.idle) ...[
          Container(
            decoration: BoxDecoration(
              color: VoxColors.surface(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: VoxColors.border(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startRecording,
                  icon: const Icon(Icons.fiber_manual_record, size: 18),
                  label: Text(
                    lang.t('record'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VoxColors.primary(context),
                    foregroundColor: VoxColors.onPrimary(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ),
        ],


        // â”€â”€ RECORDING: Show live pulse + live transcript â”€â”€
        if (_recordingState == RecordingState.recording) ...[
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF161B2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Animated mic
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (_, _) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Timer
                Text(
                  _formatDuration(_recordingDuration),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lang.tNamed('recording_time_left', {
                    'time': _formatDuration(
                      _kMaxRecordingDuration - _recordingDuration,
                    ),
                  }),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    lang.t('recording_audio_hint'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // Stop button
                GestureDetector(
                  onTap: _stopRecording,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.stop_circle_outlined,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lang.t('stop_recording'),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],

        // â”€â”€ PROCESSING â”€â”€
        if (_recordingState == RecordingState.processing) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: const Color(0xFF161B2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                CircularProgressIndicator(
                  color: Color(0xFF4B9EFF),
                  strokeWidth: 2,
                ),
                SizedBox(height: 16),
                Text(
                  lang.t('processing_audio'),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  lang.t('preparing_playback'),
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],

        // â”€â”€ DONE: Show playback + transcript â”€â”€
        if (_recordingState == RecordingState.done) ...[
          // Playback card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color(0xFF0A0E1A),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Color(0xFF4B9EFF),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      lang.t('recording_complete'),
                      style: const TextStyle(
                        color: Color(0xFF4B9EFF),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (_isUploadingAudio || _isTranscribingAudio || _transcriptionError != null)
                      Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _transcriptionError != null
                              ? Colors.red.withValues(alpha: 0.18)
                              : const Color(0xFF4B9EFF).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _transcriptionError != null
                              ? lang.t('transcription_failed_short')
                              : _isUploadingAudio
                              ? lang.t('uploading_audio')
                              : lang.t('transcribing_audio'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _transcriptionError != null
                                ? Colors.redAccent
                                : const Color(0xFF4B9EFF),
                          ),
                        ),
                      ),
                    Text(
                      _formatDuration(_recordingDuration),
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  lang.t('save_note_list_hint'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
                // Audio player
                if ((_audioUrl?.isNotEmpty ?? false) ||
                    (_audioPath != null && _audioPath!.isNotEmpty)) ...[
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _playAudio(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4B9EFF),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Color(0xFF0A0E1A),
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_formatDuration(_currentPosition)} / ${_formatDuration(_audioDuration > Duration.zero ? _audioDuration : _recordingDuration)}',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xFF4B9EFF),
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: const Color(0xFF4B9EFF),
                                  trackHeight: 2.5,
                                ),
                                child: Slider(
                                  value: _currentPosition.inSeconds
                                      .toDouble()
                                      .clamp(
                                        0,
                                        (_audioDuration > Duration.zero
                                                ? _audioDuration
                                                : _recordingDuration)
                                            .inSeconds
                                            .toDouble(),
                                      ),
                                  max: (_audioDuration > Duration.zero
                                          ? _audioDuration
                                          : _recordingDuration)
                                      .inSeconds
                                      .toDouble()
                                      .clamp(1, double.infinity),
                                  onChanged: (v) => _audioPlayer.seek(
                                    Duration(seconds: v.toInt()),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    _transcriptionError != null
                        ? lang.tNamed('audio_saved_locally_error', {
                            'error': _transcriptionError!,
                          })
                        : lang.t('audio_saved_locally'),
                    style: TextStyle(
                      color: _transcriptionError != null
                          ? Colors.redAccent
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Discard button
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFFF0F4FF),
                      title: Text(
                        lang.t('discard_recording_title'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      content: Text(lang.t('discard_recording_body')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            lang.t('keep'),
                            style: const TextStyle(color: Color(0x8A0A0E1A)),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _discardRecording();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(lang.t('discard')),
                        ),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        lang.t('discard_recording_btn'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_transcriptController.text.trim().isNotEmpty) ...[
            // Transcript edit box (only show when transcript exists)
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 14,
                          color: Color(0x730A0E1A),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          lang.t('transcript_label'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Color(0x730A0E1A),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_transcriptController.text.length} chars',
                          style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                        ),
                        if (!_isAnonymousUser &&
                            _canSaveTranscriptToDocs(_transcriptController.text))
                          IconButton(
                            tooltip: lang.t('save_transcript_to_docs'),
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 20,
                              color: Color(0xFF4B9EFF),
                            ),
                            onPressed: () => _saveCurrentEditorToSavedDocs(lang),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: _transcriptController,
                    maxLines: 6,
                    minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 14, height: 1.6),
                    decoration: InputDecoration(
                      hintText: lang.t('transcript_edit_hint'),
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    ),
                  ),
                  if (!_canSaveTranscriptToDocs(_transcriptController.text) &&
                      _transcriptController.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        lang.t('transcript_not_ready_chat'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[800],
                        ),
                      ),
                    )
                  else if (_canSaveTranscriptToDocs(_transcriptController.text))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _aiChip(
                              label: lang.t('summarize'),
                              icon: Icons.summarize_outlined,
                              dark: true,
                              onTap: () {
                                context.read<TtsService>().stop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AiResultPage(
                                      documentTitle: _editorNoteTitle(),
                                      documentContent:
                                          _transcriptController.text.trim(),
                                      mode: 'summary',
                                      source: 'Notes',
                                      outputLanguage: lang.selectedLanguage,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _aiChip(
                              label: lang.t('qa_generator'),
                              icon: Icons.style_outlined,
                              dark: false,
                              onTap: () async {
                                context.read<TtsService>().stop();
                                final count = await _pickCardCount(context);
                                if (count == null || !mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AiResultPage(
                                      documentTitle: _editorNoteTitle(),
                                      documentContent:
                                          _transcriptController.text.trim(),
                                      mode: 'flashcards',
                                      cardCount: count,
                                      source: 'Notes',
                                      outputLanguage: lang.selectedLanguage,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _aiChip(
                              label: lang.t('study_buddy'),
                              icon: Icons.psychology,
                              dark: true,
                              onTap: () {
                                context.read<TtsService>().stop();
                                _openChatBuddy(
                                  _editorNoteTitle(),
                                  _transcriptController.text,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        title: _isNoteSelectionMode
            ? ListSelectionBar(
                selectedCount: _selectedNoteIds.length,
                visibleCount: _visibleNoteIds.length,
                onCancel: _exitNoteSelectionMode,
                onToggleSelectAll: _toggleSelectAllNotes,
                onDelete: _deleteSelectedNotes,
                deleteLabel: lang.t('delete'),
                foregroundOnPrimary: true,
              )
            : Text(
                lang.t('voice_notes_title'),
                style: TextStyle(
                  color: VoxColors.onBg(context),
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
        backgroundColor: _isNoteSelectionMode
            ? VoxColors.primary(context)
            : Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: _isNoteSelectionMode
            ? null
            : [
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _isAnonymousUser
                                  ? Colors.orange
                                  : Colors.green,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            lang.selectedLanguage,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: VoxColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // â”€â”€ Guest banner â”€â”€
                  if (_isAnonymousUser) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: VoxColors.onBg(context).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: VoxColors.border(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: VoxColors.primary(context),
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Guest mode â€” notes are temporary. Sign up to keep them.',
                              style: TextStyle(
                                color: VoxColors.textSecondary(context),
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // â”€â”€ Title field â”€â”€
                  Container(
                    decoration: BoxDecoration(
                      color: VoxColors.cardFill(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: VoxColors.border(context)),
                    ),
                    child: TextField(
                      controller: _titleController,
                      maxLength: _kMaxTitleLength,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: VoxColors.onBg(context),
                        letterSpacing: -0.3,
                      ),
                      decoration: InputDecoration(
                        hintText: lang.t('note_title_field_hint'),
                        hintStyle: TextStyle(
                          color: VoxColors.textHint(context),
                          fontWeight: FontWeight.w500,
                          fontSize: 17,
                        ),
                        counterText: '',
                        border: InputBorder.none,
                        prefixIcon: Icon(
                          Icons.bookmark_border,
                          color: VoxColors.textSecondary(context),
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isTitleDictating ? Icons.mic : Icons.mic_none,
                            color: _isTitleDictating
                                ? VoxColors.primary(context)
                                : VoxColors.textSecondary(context),
                          ),
                          onPressed: () => _toggleDictation(true),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // â”€â”€ Recording area â”€â”€
                  _buildRecordingArea(lang),

                  const SizedBox(height: 16),

                  // â”€â”€ Save + Cancel/Clear buttons â”€â”€
                  if (_recordingState == RecordingState.done) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              if (_recordingState == RecordingState.done) {
                                _discardRecording();
                              } else {
                                _transcriptController.clear();
                                _titleController.clear();
                                setState(() {});
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: VoxColors.onBg(context),
                              side: BorderSide(
                                color: VoxColors.border(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              lang.t('discard'),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed:
                                (!_isSaving &&
                                    ((_transcriptController.text.trim().isNotEmpty) ||
                                        (_audioUrl?.isNotEmpty ?? false) ||
                                        _audioPath != null))
                                ? () => _saveNote(lang)
                                : null,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(Icons.save_alt, size: 18),
                            label: Text(
                              _isEditing
                                  ? lang.t('update_note')
                                  : lang.t('save_note'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: VoxColors.primary(context),
                              foregroundColor: VoxColors.onPrimary(context),
                              disabledBackgroundColor: VoxColors.cardFill(context),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_isAnonymousUser &&
                        _canSaveTranscriptToDocs(_transcriptController.text)) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _saveCurrentEditorToSavedDocs(lang),
                          icon: const Icon(Icons.folder_copy_outlined, size: 18),
                          label: Text(
                            lang.t('save_transcript_to_docs'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4B9EFF),
                            side: const BorderSide(color: Color(0xFF4B9EFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                    if (_isEditing) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _cancelEdit,
                          icon: Icon(
                            Icons.close,
                            size: 16,
                            color: VoxColors.danger,
                          ),
                          label: Text(
                            lang.t('cancel_edit'),
                            style: const TextStyle(
                              color: VoxColors.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

            // â”€â”€ Saved notes section â”€â”€
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: Divider(color: VoxColors.border(context))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lang.t('saved_notes'),
                          style: TextStyle(
                            color: VoxColors.textSecondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _isAnonymousUser
                                ? Colors.orange.withValues(alpha: 0.2)
                                : VoxColors.primary(context).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _isAnonymousUser
                                ? lang.t('guest_badge')
                                : lang.t('saved_badge'),
                            style: TextStyle(
                              color: _isAnonymousUser
                                  ? Colors.orange
                                  : VoxColors.primary(context),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[400])),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _searchQuery = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: lang.t('search_recordings'),
                  prefixIcon: Icon(
                    Icons.search,
                    color: VoxColors.textSecondary(context),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: Icon(
                            Icons.close,
                            color: VoxColors.textSecondary(context),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: VoxColors.cardFill(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: VoxColors.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: VoxColors.border(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: VoxColors.primary(context)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // â”€â”€ Notes list â”€â”€
            Consumer<TempNotesProvider>(
              builder: (context, tempNotes, _) {
                final lang = context.watch<LanguageProvider>();
                if (_isAnonymousUser) {
                  if (tempNotes.notes.isEmpty) {
                    _visibleNoteIds = [];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.mic_none_rounded,
                            color: Colors.grey[300],
                            size: 52,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            lang.t('no_notes'),
                            style: TextStyle(
                              color: VoxColors.textHint(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Record a note above to get started',
                            style: TextStyle(
                              color: VoxColors.textHint(context),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final filteredTemp = tempNotes.notes.where((note) {
                    if (_searchQuery.isEmpty) return true;
                    return note.title.toLowerCase().contains(_searchQuery);
                  }).toList();
                  _visibleNoteIds = filteredTemp.map((e) => e.id).toList();
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredTemp.length,
                    itemBuilder: (ctx, i) {
                      final note = filteredTemp[i];
                      final isSelected = _selectedNoteIds.contains(note.id);
                      return _noteCard(
                        title: note.title,
                        content: note.content,
                        hasAudio: (note.audioUrl?.isNotEmpty ?? false) ||
                            (note.audioPath?.isNotEmpty ?? false),
                        durationSeconds: note.durationSeconds,
                        isTemp: true,
                        isSelected: _isNoteSelectionMode && isSelected,
                        onTap: () {
                          if (_isNoteSelectionMode) {
                            _toggleNoteSelection(note.id);
                          } else {
                            _showNoteDetails(
                              note.id,
                              note.title,
                              note.content,
                              audioUrl: note.audioUrl,
                              audioPath: note.audioPath,
                              durationSeconds: note.durationSeconds,
                            );
                          }
                        },
                        onLongPress: () {
                          if (!_isNoteSelectionMode) {
                            _enterNoteSelectionMode(note.id);
                          }
                        },
                        onDelete: () => _deleteTempNote(note.id, tempNotes),
                      );
                    },
                  );
                }

                final notesUid = _resolvedUid;
                if (notesUid == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                return FirestoreDataGate(
                  userId: notesUid,
                  loadingMessage: 'Loading your notes...',
                  builder: (context) => StreamBuilder<QuerySnapshot>(
                    key: ValueKey('notes_$notesUid'),
                    stream: FirebaseFirestore.instance
                        .collection('notes')
                        .where('userId', isEqualTo: notesUid)
                        .snapshots(),
                    builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      if (firestoreSnapshotDenied(snapshot.error, notesUid)) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: VoxColors.primary(context),
                          ),
                        );
                      }
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            'Could not load notes',
                            style: TextStyle(color: VoxColors.textHint(context)),
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasData &&
                        firestoreSnapshotCacheOnly(snapshot.data!, notesUid)) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: VoxColors.primary(context),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final docs = List.of(snapshot.data!.docs)
                      ..sort((a, b) {
                        final aTs =
                            (a.data() as Map<String, dynamic>?)?['timestamp'];
                        final bTs =
                            (b.data() as Map<String, dynamic>?)?['timestamp'];
                        if (aTs == null && bTs == null) return 0;
                        if (aTs == null) return 1;
                        if (bTs == null) return -1;
                        return (bTs as Timestamp).compareTo(aTs as Timestamp);
                      });
                    final filteredDocs = docs.where((doc) {
                      if (_searchQuery.isEmpty) return true;
                      final data = doc.data() as Map<String, dynamic>? ?? {};
                      final title = (data['title'] as String? ?? '').toLowerCase();
                      return title.contains(_searchQuery);
                    }).toList();

                    if (filteredDocs.isEmpty) {
                      _visibleNoteIds = [];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(
                              Icons.mic_none_rounded,
                              color: Colors.grey[300],
                              size: 52,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              lang.t('no_notes'),
                              style: TextStyle(
                                color: VoxColors.textHint(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    _visibleNoteIds = filteredDocs.map((d) => d.id).toList();
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredDocs.length,
                      itemBuilder: (ctx, i) {
                        final data =
                            filteredDocs[i].data() as Map<String, dynamic>? ?? {};
                        final title = (data['title'] as String? ?? 'Note')
                            .trim();
                        final content = (data['content'] as String? ?? '')
                            .trim();
                        final audioUrl = data['audioUrl'] as String?;
                        final durationSecs =
                            data['recordingDurationSeconds'] as int?;
                        final docId = filteredDocs[i].id;
                        final isSelected = _selectedNoteIds.contains(docId);
                        return _noteCard(
                          title: title,
                          content: content,
                          hasAudio: audioUrl?.isNotEmpty ?? false,
                          durationSeconds: durationSecs,
                          isTemp: false,
                          isSelected: _isNoteSelectionMode && isSelected,
                          onTap: () {
                            if (_isNoteSelectionMode) {
                              _toggleNoteSelection(docId);
                            } else {
                              _showNoteDetails(
                                docId,
                                title,
                                content,
                                audioUrl: audioUrl,
                                durationSeconds: durationSecs,
                              );
                            }
                          },
                          onLongPress: () {
                            if (!_isNoteSelectionMode) {
                              _enterNoteSelectionMode(docId);
                            }
                          },
                          onDelete: () => _deleteNote(docId),
                        );
                      },
                    );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        color: VoxColors.surface(context),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
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
                VoxColors.primary(context),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                lang.t('nav_dictionary'),
                VoxColors.textSecondary(context),
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/dictionary'),
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
        backgroundColor: VoxColors.primary(context),
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: Icon(Icons.file_upload_outlined, color: VoxColors.onPrimary(context)),
      ),
    );
  }

  Widget _noteCard({
    required String title,
    required String content,
    required bool hasAudio,
    int? durationSeconds,
    required bool isTemp,
    bool isSelected = false,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required VoidCallback onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? VoxColors.primary(context).withValues(alpha: 0.12)
              : VoxColors.cardFill(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? VoxColors.primary(context)
                : VoxColors.border(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left icon / checkbox
            if (isSelected)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VoxColors.primary(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.check, color: VoxColors.onPrimary(context), size: 22),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasAudio
                      ? VoxColors.primary(context).withValues(alpha: 0.1)
                      : VoxColors.onBg(context).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasAudio
                        ? VoxColors.primary(context).withValues(alpha: 0.3)
                        : VoxColors.border(context),
                  ),
                ),
                child: Icon(
                  hasAudio ? Icons.mic : Icons.article_outlined,
                  color: hasAudio ? VoxColors.primary(context) : VoxColors.textSecondary(context),
                  size: 20,
                ),
              ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: VoxColors.onBg(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (isTemp)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: VoxColors.primary(context).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'TEMP',
                            style: TextStyle(
                              fontSize: 8,
                              color: Color(0xFF4B9EFF),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (hasAudio && durationSeconds != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.graphic_eq,
                          size: 11,
                          color: VoxColors.textSecondary(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(Duration(seconds: durationSeconds)),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.3),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

