import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'dart:async';
import 'language_provider.dart';
import 'temp_notes_provider.dart';
import 'tts_service.dart';
import 'ai_result_page.dart';

const int _kMaxTitleLength = 100;
const int _kMaxContentLength = 50000; // increased for long transcripts
const Duration _kMaxRecordingDuration = Duration(hours: 1);

// ─────────────────────────────────────────────
//  RECORDING STATE ENUM
// ─────────────────────────────────────────────
enum RecordingState { idle, recording, processing, done }

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
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
  String _liveTranscript = '';
  bool _isTranscribing = false;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;

  String? _resolvedUid;
  bool _isAnonymousUser = true;
  final ScrollController _scrollController = ScrollController();

  // Multi-select mode
  bool _isNoteSelectionMode = false;
  final Set<String> _selectedNoteIds = {};
  List<String> _visibleNoteIds = [];

  // Tab for note detail view
  int _detailTab = 0; // 0=transcript, 1=audio

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _speech.stop();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _titleController.dispose();
    _transcriptController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  RESOLVE USER
  // ─────────────────────────────────────────────
  Future<void> _resolveUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
        return;
      }
      if (!user.isAnonymous) {
        if (mounted) setState(() { _isAnonymousUser = false; _resolvedUid = user.uid; });
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final hasProfile = prefs.getBool('hasProfile') ?? false;
      if (!hasProfile) {
        if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
        return;
      }
      final uidDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (uidDoc.exists) {
        if (mounted) setState(() { _isAnonymousUser = false; _resolvedUid = user.uid; });
        return;
      }
      final savedEmail = prefs.getString('userEmail') ?? '';
      if (savedEmail.isNotEmpty) {
        final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: savedEmail).limit(1).get();
        if (query.docs.isNotEmpty) {
          if (mounted) setState(() { _isAnonymousUser = false; _resolvedUid = query.docs.first.id; });
          return;
        }
      }
      if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
    } catch (e) {
      if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
    }
  }

  // ─────────────────────────────────────────────
  //  MIC PERMISSION
  // ─────────────────────────────────────────────
  Future<bool> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Microphone permission denied. Enable it in Settings.'),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Settings', textColor: const Color(0xFF4B9EFF), onPressed: openAppSettings),
      ));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Microphone permission is required to record.'),
        backgroundColor: Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
      ));
    }
    return false;
  }

  // ─────────────────────────────────────────────
  //  START LONG-FORM RECORDING + LIVE TRANSCRIPTION
  // ─────────────────────────────────────────────
  Future<void> _startRecording() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a title before recording.'),
        backgroundColor: Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
      ));
      return;
    }

    final granted = await _requestMicPermission();
    if (!granted) return;

    try {
      final langProvider = context.read<LanguageProvider>();

      // Start audio recording
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: fileName,
      );

      // Start live STT transcription in parallel
      _liveTranscript = _transcriptController.text;
      _isTranscribing = true;
      _startLiveStt(langProvider.sttLocale);

      // Timers
      _recordingDuration = Duration.zero;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingDuration += const Duration(seconds: 1));
      });

      // Auto-stop at max duration
      _maxDurationTimer = Timer(_kMaxRecordingDuration, () {
        if (_recordingState == RecordingState.recording) _stopRecording();
      });

      setState(() {
        _recordingState = RecordingState.recording;
        _audioPath = fileName;
      });
    } catch (e) {
      debugPrint('Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to start recording'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _startLiveStt(String locale) async {
    bool available = await _speech.initialize(
      onError: (_) {},
      onStatus: (s) {
        // Restart STT when it stops (keeps live transcription going for long sessions)
        if ((s == 'done' || s == 'notListening') && _recordingState == RecordingState.recording && _isTranscribing) {
          Future.delayed(const Duration(milliseconds: 300), () => _startLiveStt(locale));
        }
      },
    );
    if (!available || !_isTranscribing) return;

    final existingText = _liveTranscript;
    final prefix = existingText.isNotEmpty ? '$existingText ' : '';

    _speech.listen(
      localeId: locale,
      onResult: (val) {
        String newText = val.recognizedWords;
        if (val.finalResult && newText.isNotEmpty) {
          _liveTranscript = '$prefix$newText';
          if (mounted) {
            setState(() {
              _transcriptController.text = _liveTranscript;
              _transcriptController.selection = TextSelection.fromPosition(
                TextPosition(offset: _transcriptController.text.length),
              );
            });
          }
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 6),
      partialResults: true,
    );
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    _isTranscribing = false;
    await _speech.stop();

    setState(() => _recordingState = RecordingState.processing);

    try {
      final path = await _audioRecorder.stop();
      final actualPath = path ?? _audioPath;
      _audioPath = actualPath;

      if (actualPath != null && !_isAnonymousUser) {
        await _uploadAudioToFirebase(actualPath);
      }

      setState(() => _recordingState = RecordingState.done);
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      setState(() => _recordingState = RecordingState.done);
    }
  }

  Future<void> _uploadAudioToFirebase(String localPath) async {
    if (_resolvedUid == null) return;
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = FirebaseStorage.instance.ref().child('user_notes').child(_resolvedUid!).child(fileName);
      final uploadTask = ref.putFile(File(localPath), SettableMetadata(contentType: 'audio/m4a'));
      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      setState(() => _audioUrl = downloadUrl);
      final file = File(localPath);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Error uploading audio: $e');
    }
  }

  void _discardRecording() {
    _recordingTimer?.cancel();
    _maxDurationTimer?.cancel();
    _isTranscribing = false;
    _speech.stop();
    _audioRecorder.stop();
    setState(() {
      _recordingState = RecordingState.idle;
      _audioPath = null;
      _audioUrl = null;
      _recordingDuration = Duration.zero;
      _audioDuration = Duration.zero;
      _currentPosition = Duration.zero;
      _isPlaying = false;
      _liveTranscript = '';
      _transcriptController.clear();
    });
  }

  // ─────────────────────────────────────────────
  //  PLAYBACK
  // ─────────────────────────────────────────────
  Future<void> _playAudio({String? url}) async {
    final targetUrl = url ?? _audioUrl;
    if (targetUrl == null) return;
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
        setState(() => _isPlaying = false);
      } else {
        await _audioPlayer.setUrl(targetUrl);
        _audioPlayer.positionStream.listen((p) { if (mounted) setState(() => _currentPosition = p); });
        _audioPlayer.durationStream.listen((d) { if (d != null && mounted) setState(() => _audioDuration = d); });
        _audioPlayer.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            if (mounted) setState(() { _isPlaying = false; _currentPosition = Duration.zero; });
          }
        });
        await _audioPlayer.play();
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────
  //  SAVE NOTE
  // ─────────────────────────────────────────────
  Future<void> _saveNote(LanguageProvider lang) async {
    final transcript = _transcriptController.text.trim();
    final rawTitle = _titleController.text.trim();
    final title = rawTitle.isNotEmpty ? rawTitle : 'Note';

    if (rawTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please add a title before saving.'),
        backgroundColor: Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
      ));
      return;
    }
    if (transcript.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transcript is empty. Please record or type content.'),
        backgroundColor: Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
      ));
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditing && _editingId != null) {
        if (_isAnonymousUser) {
          context.read<TempNotesProvider>().update(_editingId!, title, transcript);
        } else {
          await FirebaseFirestore.instance.collection('notes').doc(_editingId).update({
            'title': title,
            'content': transcript,
            'audioUrl': _audioUrl,
            'recordingDurationSeconds': _recordingDuration.inSeconds,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      } else {
        if (_isAnonymousUser) {
          context.read<TempNotesProvider>().add(title, transcript);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Note saved temporarily. Create an account to keep it.'),
              backgroundColor: Color(0xFF333333),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
            ));
          }
        } else {
          final authUid = FirebaseAuth.instance.currentUser?.uid ?? _resolvedUid!;
          await FirebaseFirestore.instance.collection('notes').add({
            'userId': authUid,
            'title': title,
            'content': transcript,
            'audioUrl': _audioUrl,
            'recordingDurationSeconds': _recordingDuration.inSeconds,
            'timestamp': FieldValue.serverTimestamp(),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(lang.t('note_saved')),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF333333),
              margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _titleController.clear();
          _transcriptController.clear();
          _liveTranscript = '';
          _isEditing = false;
          _editingId = null;
          _audioPath = null;
          _audioUrl = null;
          _recordingState = RecordingState.idle;
          _recordingDuration = Duration.zero;
          _audioDuration = Duration.zero;
          _currentPosition = Duration.zero;
          _isPlaying = false;
        });
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.code == 'unavailable' ? 'No internet. Note will sync when back online.' : '${lang.t('error_saving')} ${e.message}'),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${lang.t('error_saving')} $e'),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─────────────────────────────────────────────
  //  DELETE
  // ─────────────────────────────────────────────
  Future<void> _deleteNote(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Note?'),
          ],
        ),
        content: const Text('This item will be stored in the Recycle Bin and permanently deleted after 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0x8A0A0E1A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Delete'),
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
        final targetUid = data['userId']?.toString() ?? FirebaseAuth.instance.currentUser?.uid ?? _resolvedUid;
        if (targetUid != null) {
          await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('deleted_library').add({
            'fileName': data['title'] ?? 'Note',
            'content': data['content'],
            'audioUrl': data['audioUrl'],
            'recordingDurationSeconds': data['recordingDurationSeconds'],
            'fileType': 'note',
            'sourceCollection': 'notes',
            'deletedAt': FieldValue.serverTimestamp(),
            'originalTimestamp': data['timestamp'] ?? FieldValue.serverTimestamp(),
            'userId': data['userId'] ?? targetUid,
          });
        }
      }
      await docRef.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.delete_sweep_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${noteTitle != null ? '"$noteTitle" moved' : 'Note moved'} to Recycle Bin. Kept for 30 days.',
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
        ));
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.code == 'unavailable' ? 'Cannot delete while offline.' : 'Delete failed: ${e.message}'),
          backgroundColor: const Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _deleteTempNote(String id, TempNotesProvider tempNotes) {
    tempNotes.remove(id);
    if (_isEditing && _editingId == id) _cancelEdit();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Note deleted.'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF333333),
      margin: EdgeInsets.only(bottom: 30, left: 20, right: 20),
    ));
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _editingId = null;
      _titleController.clear();
      _transcriptController.clear();
      _liveTranscript = '';
      _recordingState = RecordingState.idle;
      _audioPath = null;
      _audioUrl = null;
      _recordingDuration = Duration.zero;
    });
  }

  // ─────────────────────────────────────────────
  //  SELECTION MODE HELPERS
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  //  DELETE SELECTED NOTES
  // ─────────────────────────────────────────────
  Future<void> _deleteSelectedNotes() async {
    if (_selectedNoteIds.isEmpty) return;
    final count = _selectedNoteIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Selected?'),
          ],
        ),
        content: Text('$count note${count == 1 ? '' : 's'} will be moved to the Recycle Bin and permanently deleted after 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0x8A0A0E1A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Delete $count'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      if (_isAnonymousUser) {
        final provider = context.read<TempNotesProvider>();
        for (var id in _selectedNoteIds.toList()) {
          provider.remove(id);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count note${count == 1 ? '' : 's'} deleted.'), backgroundColor: const Color(0xFF333333)));
        }
      } else {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? _resolvedUid;
        if (uid == null) return;

        final batch = FirebaseFirestore.instance.batch();
        final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

        for (var docId in _selectedNoteIds) {
          final docRef = FirebaseFirestore.instance.collection('notes').doc(docId);
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
              'originalTimestamp': data['timestamp'] ?? FieldValue.serverTimestamp(),
              'userId': uid,
            });
            batch.delete(docRef);
          }
        }
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count note${count == 1 ? '' : 's'} moved to Recycle Bin.'), backgroundColor: const Color(0xFF333333)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent));
      }
    }

    _exitNoteSelectionMode();
  }

  // ─────────────────────────────────────────────
  //  NOTE DETAIL BOTTOM SHEET
  // ─────────────────────────────────────────────
  void _showNoteDetails(String id, String title, String content, {String? audioUrl, int? durationSeconds}) {
    final lang = context.read<LanguageProvider>();
    final tts = context.read<TtsService>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final popupTitleController = TextEditingController(text: title);
        final popupContentController = TextEditingController(text: content);
        bool isEditMode = false;
        bool isSaving = false;
        bool isSpeaking = false;
        int activeTab = 0; // 0=transcript, 1=audio
        AudioPlayer localPlayer = AudioPlayer();
        bool isPlayingLocal = false;
        Duration localPos = Duration.zero;
        Duration localDur = Duration.zero;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          tts.play(title, content, lang.ttsLocale);
          isSpeaking = true;
        });

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F4FF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                          decoration: BoxDecoration(color: Color(0x420A0E1A), borderRadius: BorderRadius.circular(10)),
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
                              child: isEditMode
                                  ? TextField(
                                      controller: popupTitleController,
                                      autofocus: true,
                                      maxLength: _kMaxTitleLength,
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        hintText: 'Title',
                                        counterText: '',
                                        filled: true,
                                        fillColor: Color(0xFF0A0E1A).withValues(alpha: 0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    )
                                  : Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                            ),
                            if (!isEditMode) ...[
                              _sheetIconBtn(
                                icon: isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
                                color: isSpeaking ? const Color(0xFF4B9EFF) : Color(0x8A0A0E1A),
                                onTap: () {
                                  if (isSpeaking) { tts.stop(); setSheetState(() => isSpeaking = false); }
                                  else { tts.play(title, content, lang.ttsLocale); setSheetState(() => isSpeaking = true); }
                                },
                              ),
                              _sheetIconBtn(
                                icon: Icons.edit_note_rounded,
                                color: Color(0x8A0A0E1A),
                                onTap: () {
                                  tts.stop();
                                  setSheetState(() { isEditMode = true; isSpeaking = false; });
                                },
                              ),
                            ] else ...[
                              _sheetIconBtn(icon: Icons.close, color: Color(0x610A0E1A), onTap: () {
                                popupTitleController.text = title;
                                popupContentController.text = content;
                                setSheetState(() => isEditMode = false);
                              }),
                              isSaving
                                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A0E1A))))
                                  : _sheetIconBtn(icon: Icons.check_rounded, color: Color(0xDD0A0E1A), onTap: () async {
                                      final newTitle = popupTitleController.text.trim();
                                      final newContent = popupContentController.text.trim();
                                      if (newTitle.isEmpty || newContent.isEmpty) return;
                                      setSheetState(() => isSaving = true);
                                      try {
                                        if (_isAnonymousUser) {
                                          context.read<TempNotesProvider>().update(id, newTitle, newContent);
                                        } else {
                                          await FirebaseFirestore.instance.collection('notes').doc(id).update({
                                            'title': newTitle, 'content': newContent, 'lastUpdated': FieldValue.serverTimestamp(),
                                          });
                                        }
                                        if (context.mounted) { Navigator.pop(ctx); }
                                      } catch (e) { setSheetState(() => isSaving = false); }
                                    }),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 4),
                      if (durationSeconds != null && durationSeconds > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, bottom: 4),
                          child: Row(
                            children: [
                              Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(_formatDuration(Duration(seconds: durationSeconds)),
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                        ),

                      // ── AI Tools bar ──
                      if (!isEditMode) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Color(0xFF0A0E1A),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF4B9EFF)),
                                const SizedBox(width: 6),
                                const Text('AI Tools', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF4B9EFF))),
                                const Spacer(),
                                _aiChip(label: 'Summarize', icon: Icons.summarize_outlined, dark: true, onTap: () {
                                  tts.stop(); Navigator.pop(ctx);
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => AiResultPage(documentTitle: title, documentContent: content, mode: 'summary')));
                                }),
                                const SizedBox(width: 8),
                                _aiChip(label: 'Assessment', icon: Icons.style_outlined, dark: false, onTap: () async {
                                  tts.stop();
                                  final count = await _pickCardCount(context);
                                  if (count == null || !context.mounted) return;
                                  Navigator.pop(ctx);
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => AiResultPage(documentTitle: title, documentContent: content, mode: 'flashcards', cardCount: count)));
                                }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── Tabs ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              _tabChip(label: 'Transcript', selected: activeTab == 0, onTap: () => setSheetState(() => activeTab = 0)),
                              const SizedBox(width: 8),
                              if (audioUrl != null)
                                _tabChip(label: 'Audio', selected: activeTab == 1, onTap: () => setSheetState(() => activeTab = 1)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20),

                      // ── Body ──
                      Expanded(
                        child: isEditMode
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: TextField(
                                  controller: popupContentController,
                                  maxLines: null,
                                  expands: true,
                                  maxLength: _kMaxContentLength,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: const TextStyle(fontSize: 15, height: 1.7),
                                  decoration: InputDecoration(
                                    hintText: 'Transcript...',
                                    counterText: '',
                                    filled: true,
                                    fillColor: Color(0xFF0A0E1A).withValues(alpha: 0.04),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.all(14),
                                  ),
                                ),
                              )
                            : activeTab == 0
                                ? ListView(
                                    controller: scrollController,
                                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                                    children: [
                                      Text(content, style: const TextStyle(fontSize: 15, height: 1.75, color: Color(0xDD0A0E1A))),
                                    ],
                                  )
                                : _audioPlayerPanel(
                                    audioUrl: audioUrl!,
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
    ).whenComplete(() { tts.stop(); });
  }

  Widget _audioPlayerPanel({
    required String audioUrl,
    required bool isPlayingLocal,
    required Duration localPos,
    required Duration localDur,
    required AudioPlayer localPlayer,
    required void Function(bool playing, Duration pos, Duration dur) onStateChanged,
  }) {
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
                    const Text('Voice Recording', style: TextStyle(color: Color(0xFF4B9EFF), fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    try {
                      if (isPlayingLocal) {
                        await localPlayer.pause();
                        onStateChanged(false, localPos, localDur);
                      } else {
                        await localPlayer.setUrl(audioUrl);
                        localPlayer.positionStream.listen((p) => onStateChanged(true, p, localDur));
                        localPlayer.durationStream.listen((d) { if (d != null) onStateChanged(true, localPos, d); });
                        localPlayer.playerStateStream.listen((s) {
                          if (s.processingState == ProcessingState.completed) {
                            onStateChanged(false, Duration.zero, localDur);
                          }
                        });
                        await localPlayer.play();
                        onStateChanged(true, localPos, localDur);
                      }
                    } catch (e) { debugPrint('Error: $e'); }
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B9EFF),
                      borderRadius: BorderRadius.circular(36),
                    ),
                    child: Icon(isPlayingLocal ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Color(0xFF0A0E1A), size: 36),
                  ),
                ),
                const SizedBox(height: 16),
                if (localDur > Duration.zero) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(localPos), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(_formatDuration(localDur), style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
                      value: localPos.inSeconds.toDouble().clamp(0, localDur.inSeconds.toDouble()),
                      max: localDur.inSeconds.toDouble(),
                      onChanged: (v) => localPlayer.seek(Duration(seconds: v.toInt())),
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

  Widget _sheetIconBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _aiChip({required String label, required IconData icon, required bool dark, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFF4B9EFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: dark ? const Color(0xFF4B9EFF) : Color(0xFF0A0E1A), size: 12),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: dark ? const Color(0xFF4B9EFF) : Color(0xFF0A0E1A), fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _tabChip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Color(0xFF0A0E1A) : Color(0xFF0A0E1A).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: selected ? const Color(0xFF4B9EFF) : Color(0x8A0A0E1A), fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<int?> _pickCardCount(BuildContext context) async {
    int selected = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFF0F4FF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('How many questions?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$selected cards', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF4B9EFF))),
              Slider(
                value: selected.toDouble(), min: 5, max: 20, divisions: 15,
                activeColor: Color(0xFF0A0E1A), inactiveColor: Colors.grey[300],
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('5', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  Text('20', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0x8A0A0E1A)))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF0A0E1A), foregroundColor: const Color(0xFF4B9EFF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  RECORDING AREA WIDGET
  // ─────────────────────────────────────────────
  Widget _buildRecordingArea(LanguageProvider lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── IDLE: Show typable text area + record button ──
        if (_recordingState == RecordingState.idle) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _transcriptController,
                  maxLines: 8,
                  minLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'Type your note here...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                GestureDetector(
                  onTap: _startRecording,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0A0E1A),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.mic, color: Color(0xFF4B9EFF), size: 18),
                        const SizedBox(width: 8),
                        const Text('Voice Record', style: TextStyle(color: Color(0xFF4B9EFF), fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── RECORDING: Show live pulse + live transcript ──
        if (_recordingState == RecordingState.recording) ...[
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Color(0xFF0A0E1A), borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Animated mic
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (_, __) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 24, spreadRadius: 6)],
                      ),
                      child: const Icon(Icons.mic, color: Colors.white, size: 34),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Timer
                Text(_formatDuration(_recordingDuration),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 2)),
                const SizedBox(height: 4),
                Text('Recording · ${_formatDuration(_kMaxRecordingDuration - _recordingDuration)} left',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),

                // Live transcript preview
                if (_transcriptController.text.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(maxHeight: 80),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _transcriptController.text,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.5),
                      ),
                    ),
                  ),
                ],

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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 20),
                        SizedBox(width: 8),
                        Text('Stop Recording', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],

        // ── PROCESSING ──
        if (_recordingState == RecordingState.processing) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(color: Color(0xFF0A0E1A), borderRadius: BorderRadius.circular(24)),
            child: const Column(
              children: [
                CircularProgressIndicator(color: Color(0xFF4B9EFF), strokeWidth: 2),
                SizedBox(height: 16),
                Text('Processing audio...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Uploading & finalising transcript', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],

        // ── DONE: Show playback + transcript ──
        if (_recordingState == RecordingState.done) ...[
          // Playback card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Color(0xFF0A0E1A), borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF4B9EFF), size: 18),
                    const SizedBox(width: 8),
                    const Text('Recording complete', style: TextStyle(color: Color(0xFF4B9EFF), fontWeight: FontWeight.w700, fontSize: 13)),
                    const Spacer(),
                    Text(_formatDuration(_recordingDuration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 16),
                // Audio player
                if (_audioUrl != null) ...[
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _playAudio,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: const Color(0xFF4B9EFF), borderRadius: BorderRadius.circular(24)),
                          child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Color(0xFF0A0E1A), size: 26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_audioDuration > Duration.zero)
                              Text('${_formatDuration(_currentPosition)} / ${_formatDuration(_audioDuration)}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            const SizedBox(height: 4),
                            if (_audioDuration > Duration.zero)
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: const Color(0xFF4B9EFF),
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: const Color(0xFF4B9EFF),
                                  trackHeight: 2.5,
                                ),
                                child: Slider(
                                  value: _currentPosition.inSeconds.toDouble().clamp(0, _audioDuration.inSeconds.toDouble()),
                                  max: _audioDuration.inSeconds.toDouble(),
                                  onChanged: (v) => _audioPlayer.seek(Duration(seconds: v.toInt())),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text('Audio saved locally', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                // Discard button
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFFF0F4FF),
                      title: const Text('Discard recording?', style: TextStyle(fontWeight: FontWeight.bold)),
                      content: const Text('This will delete the audio and transcript.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep', style: TextStyle(color: Color(0x8A0A0E1A)))),
                        ElevatedButton(
                          onPressed: () { Navigator.pop(ctx); _discardRecording(); },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white.withValues(alpha: 0.3), size: 14),
                      const SizedBox(width: 4),
                      Text('Discard recording', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Transcript edit box
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
                      const Icon(Icons.article_outlined, size: 14, color: Color(0x730A0E1A)),
                      const SizedBox(width: 6),
                      const Text('Transcript', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0x730A0E1A))),
                      const Spacer(),
                      Text('${_transcriptController.text.length} chars', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                    ],
                  ),
                ),
                TextField(
                  controller: _transcriptController,
                  maxLines: 6,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 14, height: 1.6),
                  decoration: const InputDecoration(
                    hintText: 'Transcript appears here. Edit if needed...',
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: _isNoteSelectionMode
            ? Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF0A0E1A), size: 22),
                    onPressed: _exitNoteSelectionMode,
                  ),
                  Text(
                    '${_selectedNoteIds.length} selected',
                    style: const TextStyle(color: Color(0xFF0A0E1A), fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ],
              )
            : const Text('Voice Notes', style: TextStyle(color: Color(0xFF0A0E1A), fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5)),
        backgroundColor: _isNoteSelectionMode ? const Color(0xFF4B9EFF).withOpacity(0.1) : Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: _isNoteSelectionMode
            ? [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (_selectedNoteIds.length == _visibleNoteIds.length && _visibleNoteIds.isNotEmpty) {
                        _selectedNoteIds.clear();
                      } else {
                        _selectedNoteIds.addAll(_visibleNoteIds);
                      }
                    });
                  },
                  icon: Icon(
                    _selectedNoteIds.length == _visibleNoteIds.length && _visibleNoteIds.isNotEmpty ? Icons.deselect : Icons.select_all,
                    color: const Color(0xFF0A0E1A),
                    size: 18,
                  ),
                  label: Text(
                    _selectedNoteIds.length == _visibleNoteIds.length && _visibleNoteIds.isNotEmpty ? 'Deselect' : 'Select All',
                    style: const TextStyle(color: Color(0xFF0A0E1A), fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ElevatedButton.icon(
                    onPressed: _selectedNoteIds.isNotEmpty ? _deleteSelectedNotes : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ]
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Color(0xFF0A0E1A).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: _isAnonymousUser ? Colors.orange : Colors.green, borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 5),
                          Text(lang.selectedLanguage, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xDD0A0E1A))),
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
                  // ── Guest banner ──
                  if (_isAnonymousUser) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange, size: 14),
                          SizedBox(width: 8),
                          Expanded(child: Text('Guest mode — notes are temporary. Sign up to keep them.', style: TextStyle(color: Color(0x8A0A0E1A), fontSize: 11, height: 1.4))),
                        ],
                      ),
                    ),
                  ],

                  // ── Title field ──
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: _titleController,
                      maxLength: _kMaxTitleLength,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -0.3),
                      decoration: InputDecoration(
                        hintText: 'Note title...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w500, fontSize: 17),
                        counterText: '',
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.bookmark_border, color: Color(0x610A0E1A), size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Recording area ──
                  _buildRecordingArea(lang),

                  const SizedBox(height: 16),

                  // ── Save + Cancel/Clear buttons ──
                  if (_recordingState == RecordingState.done || (_recordingState == RecordingState.idle && _transcriptController.text.trim().isNotEmpty)) ...[
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
                              foregroundColor: Color(0x8A0A0E1A),
                              side: BorderSide(color: Colors.grey[400]!),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Discard', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: (!_isSaving && _transcriptController.text.trim().isNotEmpty) ? () => _saveNote(lang) : null,
                            icon: _isSaving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_alt, size: 18),
                            label: Text(_isEditing ? 'Update Note' : 'Save Note', style: const TextStyle(fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF0A0E1A),
                              foregroundColor: const Color(0xFF4B9EFF),
                              disabledBackgroundColor: Colors.grey[300],
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _cancelEdit,
                          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          label: const Text('Cancel Edit', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),

            // ── Saved notes section ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[400])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(lang.t('saved_notes'), style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _isAnonymousUser ? Colors.orange[100] : Color(0xFF0A0E1A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _isAnonymousUser ? 'GUEST' : 'SAVED',
                            style: TextStyle(color: _isAnonymousUser ? Colors.orange[800] : const Color(0xFF4B9EFF), fontSize: 9, fontWeight: FontWeight.w800),
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

            // ── Notes list ──
            Consumer<TempNotesProvider>(
              builder: (context, tempNotes, _) {
                if (_isAnonymousUser) {
                  if (tempNotes.notes.isEmpty) {
                    _visibleNoteIds = [];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.mic_none_rounded, color: Colors.grey[300], size: 52),
                          const SizedBox(height: 10),
                          Text(lang.t('no_notes'), style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Record a note above to get started', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                        ],
                      ),
                    );
                  }
                  _visibleNoteIds = tempNotes.notes.map((e) => e.id).toList();
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: tempNotes.notes.length,
                    itemBuilder: (ctx, i) {
                      final note = tempNotes.notes[i];
                      final isSelected = _selectedNoteIds.contains(note.id);
                      return _noteCard(
                        title: note.title,
                        content: note.content,
                        hasAudio: false,
                        isTemp: true,
                        isSelected: _isNoteSelectionMode && isSelected,
                        onTap: () {
                          if (_isNoteSelectionMode) {
                            _toggleNoteSelection(note.id);
                          } else {
                            _showNoteDetails(note.id, note.title, note.content);
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

                if (_resolvedUid == null) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('notes')
                      .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? _resolvedUid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text('Could not load notes', style: TextStyle(color: Colors.grey[500])),
                        ),
                      );
                    }
                    if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));

                    final docs = List.of(snapshot.data!.docs)
                      ..sort((a, b) {
                        final aTs = (a.data() as Map<String, dynamic>?)?['timestamp'];
                        final bTs = (b.data() as Map<String, dynamic>?)?['timestamp'];
                        if (aTs == null && bTs == null) return 0;
                        if (aTs == null) return 1;
                        if (bTs == null) return -1;
                        return (bTs as Timestamp).compareTo(aTs as Timestamp);
                      });

                    if (docs.isEmpty) {
                      _visibleNoteIds = [];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(Icons.mic_none_rounded, color: Colors.grey[300], size: 52),
                            const SizedBox(height: 10),
                            Text(lang.t('no_notes'), style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    }

                    _visibleNoteIds = docs.map((d) => d.id).toList();
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final data = docs[i].data() as Map<String, dynamic>? ?? {};
                        final title = (data['title'] as String? ?? 'Note').trim();
                        final content = (data['content'] as String? ?? '').trim();
                        final audioUrl = data['audioUrl'] as String?;
                        final durationSecs = data['recordingDurationSeconds'] as int?;
                        final docId = docs[i].id;
                        final isSelected = _selectedNoteIds.contains(docId);
                        return _noteCard(
                          title: title,
                          content: content,
                          hasAudio: audioUrl != null,
                          durationSeconds: durationSecs,
                          isTemp: false,
                          isSelected: _isNoteSelectionMode && isSelected,
                          onTap: () {
                            if (_isNoteSelectionMode) {
                              _toggleNoteSelection(docId);
                            } else {
                              _showNoteDetails(docId, title, content, audioUrl: audioUrl, durationSeconds: durationSecs);
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
                );
              },
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        color: Color(0xFF141A29),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 65,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home, lang.t('nav_home'), Colors.grey[400]!, onTap: () => Navigator.pushReplacementNamed(context, '/home')),
              _navItem(Icons.note_alt_outlined, lang.t('nav_notes'), Colors.white),
              const SizedBox(width: 48),
              _navItem(Icons.book, lang.t('nav_dictionary'), Colors.grey[400]!, onTap: () => Navigator.pushReplacementNamed(context, '/dictionary')),
              _navItem(Icons.menu, lang.t('nav_menu'), Colors.grey[400]!, onTap: () => Navigator.pushReplacementNamed(context, '/menu')),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF0A0E1A),
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: const Icon(Icons.file_upload_outlined, color: Colors.white),
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
          color: isSelected ? const Color(0xFF4B9EFF).withOpacity(0.12) : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF4B9EFF) : Color(0xFF0A0E1A).withValues(alpha: 0.05),
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
                  color: const Color(0xFF4B9EFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 22),
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasAudio ? Color(0xFF0A0E1A) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(hasAudio ? Icons.mic : Icons.article_outlined, color: hasAudio ? const Color(0xFF4B9EFF) : Colors.grey[500], size: 20),
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
                        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: -0.2)),
                      ),
                      if (isTemp)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: Color(0xFF0A0E1A).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(5)),
                          child: const Text('TEMP', style: TextStyle(fontSize: 8, color: Color(0x730A0E1A), fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4)),
                  if (hasAudio && durationSeconds != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.graphic_eq, size: 11, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(_formatDuration(Duration(seconds: durationSeconds)), style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600)),
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

  Widget _navItem(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}