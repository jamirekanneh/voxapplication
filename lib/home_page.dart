import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'reader_page.dart';
import 'mini_player_bar.dart';
import 'temp_library_provider.dart';
import 'ai_result_page.dart';
import 'custom_commands_provider.dart';
import 'theme_provider.dart';
import 'analytics_service.dart';

class VoxHomePage extends StatefulWidget {
  const VoxHomePage({super.key});

  @override
  State<VoxHomePage> createState() => _VoxHomePageState();
}

class _VoxHomePageState extends State<VoxHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _searchQuery = '';
  bool _isListening = false;
  StreamSubscription<int>? _streakSubscription;

  String _selectedFolder = 'All Files';
  final List<String> _folders = ['All Files', 'PDFs', 'Documents', 'Scans'];

  // Multi-select mode
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  List<String> _visibleIds = [];

  String? _resolvedUid;
  bool _isAnonymousUser = true;

  @override
  void initState() {
    super.initState();
    _resolveUser();

    _streakSubscription = AnalyticsService.instance.onStreakMilestone.listen((streak) {
      if (mounted) {
        _showStreakMilestoneDialog(streak);
      }
    });

    // Wire assistant commands after first frame so context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerAssistantHandler();
    });
  }

  void _registerAssistantHandler() {
    final provider = context.read<CustomCommandsProvider>();
    provider.onCommand = (command) {
      if (!mounted) return;

      switch (command.type) {
        case AssistantCommandType.navigate:
          if (command.route != null) {
            Navigator.pushNamed(context, command.route!);
          }
          break;

        case AssistantCommandType.search:
          setState(() {
            _searchQuery = command.payload!.toLowerCase();
            _searchController.text = command.payload!;
          });
          _showAssistantFeedback('Searching for "${command.payload}"');
          break;

        case AssistantCommandType.openFile:
          // Filter library to match and auto-open first result
          setState(() {
            _searchQuery = command.payload!.toLowerCase();
            _searchController.text = command.payload!;
          });
          _showAssistantFeedback('Opening "${command.payload}"');
          break;

        case AssistantCommandType.stopAssistant:
          provider.setAssistantMode(false);
          _showAssistantFeedback('Assistant off');
          break;
      }
    };
  }

  void _showAssistantFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.graphic_eq_rounded,
                color: VoxColors.primary(context), size: 16),
            const SizedBox(width: 8),
            Text(message, style: TextStyle(color: VoxColors.onSurface(context))),
          ],
        ),
        backgroundColor: VoxColors.surface(context),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.only(bottom: 90, left: 20, right: 20),
      ),
    );
  }

  void _showStreakMilestoneDialog(int streak) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VoxColors.bg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉✨🎈', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'Amazing Job!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: VoxColors.primary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You hit a $streak Day Reading Streak!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: VoxColors.onBg(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: VoxColors.primary(context),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Keep it up!'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args.containsKey('searchQuery')) {
      final query = args['searchQuery'] as String;
      if (query.isNotEmpty) {
        setState(() {
          _searchQuery = query.toLowerCase();
          _searchController.text = query;
        });
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _searchController.dispose();
    _streakSubscription?.cancel();
    super.dispose();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  RESOLVE USER
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _resolveUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = true;
          _resolvedUid = null;
        });
      }
      return;
    }

    if (!user.isAnonymous) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = false;
          _resolvedUid = user.uid;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.getBool('hasProfile') ?? false;

    if (!hasProfile) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = true;
          _resolvedUid = null;
        });
      }
      return;
    }

    final uidDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (uidDoc.exists) {
      if (mounted) {
        setState(() {
          _isAnonymousUser = false;
          _resolvedUid = user.uid;
        });
      }
      return;
    }

    final savedEmail = prefs.getString('userEmail') ?? '';
    if (savedEmail.isNotEmpty) {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: savedEmail)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final docUid = query.docs.first.id;
        if (mounted) {
          setState(() {
            _isAnonymousUser = false;
            _resolvedUid = docUid;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isAnonymousUser = true;
        _resolvedUid = null;
      });
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  DOCUMENT OPTIONS (3 buttons)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _showDocumentOptions(String fileName, String content) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VoxColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Text(
              fileName,
              style: TextStyle(
                color: VoxColors.onSurface(context),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'What would you like to do?',
              style: TextStyle(color: VoxColors.textSecondary(context), fontSize: 13),
            ),
            const SizedBox(height: 20),
            _docOptionTile(
              ctx,
              icon: Icons.headphones_rounded,
              iconColor: VoxColors.primary(context),
              title: 'Read Document',
              subtitle: 'Listen to the document read aloud',
              value: 'read',
            ),
            const SizedBox(height: 10),
            _docOptionTile(
              ctx,
              icon: Icons.summarize_outlined,
              iconColor: Colors.blue[300]!,
              title: 'Summarize',
              subtitle: 'Get an AI-powered summary of the document',
              value: 'summary',
            ),
            const SizedBox(height: 10),
            _docOptionTile(
              ctx,
              icon: Icons.style_outlined,
              iconColor: Colors.green[300]!,
              title: 'Q&A Generator',
              subtitle: 'Create a study Q&A set from the document',
              value: 'flashcards',
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'read') {
      final locale = context.read<LanguageProvider>().ttsLocale;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: context.read<TtsService>()),
              ChangeNotifierProvider.value(
                value: context.read<LanguageProvider>(),
              ),
            ],
            child: ReaderPage(
              title: fileName,
              content: content,
              locale: locale,
            ),
          ),
        ),
      );
    } else {
      // Show card count picker for flashcards
      int? cardCount;
      if (choice == 'flashcards') {
        cardCount = await _pickCardCount(context);
        if (cardCount == null || !mounted) return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AiResultPage(
            documentTitle: fileName,
            documentContent: content,
            mode: choice,
            cardCount: cardCount ?? 10,
          ),
        ),
      );
    }
  }

  Widget _docOptionTile(
    BuildContext ctx, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VoxColors.surface2(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: VoxColors.onSurface(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: VoxColors.textSecondary(context), fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  OPEN READER (kept for backward compatibility)
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _openReader(String fileName, String content) async {
    await _showDocumentOptions(fileName, content);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  VOICE SEARCH
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _listen() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied'),
            backgroundColor: VoxColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    bool available = await _speech.initialize(
      onError: (e) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (!available || !mounted) return;
    final langProvider = context.read<LanguageProvider>();
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: langProvider.sttLocale,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.search,
      ),
      onResult: (val) {
        if (!mounted) return;
        setState(() {
          _searchQuery = val.recognizedWords.toLowerCase();
          _searchController.text = val.recognizedWords;
        });
      },
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  SELECTION MODE HELPERS
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _enterSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  DELETE SELECTED
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
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
            Text('Delete Selected?', style: TextStyle(color: VoxColors.onSurface(context))),
          ],
        ),
        content: Text(
          '$count file${count == 1 ? '' : 's'} will be moved to the Recycle Bin and permanently deleted after 30 days.',
          style: TextStyle(color: VoxColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: VoxColors.textSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: VoxColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete $count'),
          ),
        ],
      ),

    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      if (_isAnonymousUser) {
        final provider = context.read<TempLibraryProvider>();
        for (var id in _selectedIds.toList()) {
          provider.remove(id);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count file${count == 1 ? '' : 's'} deleted.'), backgroundColor: VoxColors.surface(context)));
        }
      } else {
        final uid = _resolvedUid ?? FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return;

        final batch = FirebaseFirestore.instance.batch();
        final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

        for (var docId in _selectedIds) {
          final docRef = FirebaseFirestore.instance.collection('library').doc(docId);
          final snapshot = await docRef.get();
          if (snapshot.exists) {
            final data = snapshot.data()!;
            final newDocRef = userDoc.collection('deleted_library').doc();
            batch.set(newDocRef, {
              'fileName': data['fileName'] ?? 'File',
              'content': data['content'],
              'fileType': data['fileType'] ?? 'file',
              'sourceCollection': 'library',
              'deletedAt': FieldValue.serverTimestamp(),
              'originalTimestamp': data['timestamp'] ?? FieldValue.serverTimestamp(),
              'userId': uid,
            });
            batch.delete(docRef);
          }
        }
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count file${count == 1 ? '' : 's'} moved to Recycle Bin.'), backgroundColor: VoxColors.surface(context)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e'), backgroundColor: VoxColors.danger));
      }
    }

    _exitSelectionMode();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    return Scaffold(
      backgroundColor: VoxColors.bg(context), // Vox Dark Navy
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // â”€â”€ Header / Selection Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              if (_isSelectionMode) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: VoxColors.bg(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close, color: VoxColors.onBg(context), size: 22),
                        onPressed: _exitSelectionMode,
                        tooltip: 'Cancel',
                      ),
                      Text(
                        '${_selectedIds.length} selected',
                        style: TextStyle(color: VoxColors.onBg(context), fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            if (_selectedIds.length == _visibleIds.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds.addAll(_visibleIds);
                            }
                          });
                        },
                        icon: Icon(_selectedIds.length == _visibleIds.length ? Icons.deselect : Icons.select_all, color: VoxColors.primary(context), size: 18),
                        label: Text(_selectedIds.length == _visibleIds.length ? 'Deselect' : 'Select All', style: TextStyle(color: VoxColors.primary(context), fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton.icon(
                        onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
                        icon: Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VoxColors.danger,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: VoxColors.border(context),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text("Vox",
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: Colors.white, // Keep white for header if it's primary blue?
                                letterSpacing: 2)),
                        const SizedBox(width: 12),
                      ],
                    ),
                    SizedBox(
                      width: 180,
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        maxLength: 100,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: lang.t('search_hint'),
                          counterText: '',
                          prefixIcon: Icon(Icons.search, size: 18, color: VoxColors.onBg(context).withValues(alpha: 0.5)),
                          suffixIcon: GestureDetector(
                            onTap: _listen,
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              size: 18,
                              color: _isListening
                                  ? VoxColors.danger
                                  : VoxColors.onBg(context).withValues(alpha: 0.4),
                            ),
                          ),
                          filled: true,
                          fillColor: VoxColors.onBg(context).withValues(alpha: 0.08),
                          hoverColor: VoxColors.onBg(context).withValues(alpha: 0.12),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Consumer<CustomCommandsProvider>(
                      builder: (context, provider, _) => Tooltip(
                        message: 'Assistant Mode (Voice Activated)',
                        child: GestureDetector(
                          onTap: () => provider
                              .setAssistantMode(!provider.assistantModeEnabled),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: provider.assistantModeEnabled
                                  ? VoxColors.primary(context).withValues(alpha: 0.15)
                                  : VoxColors.onBg(context).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: provider.assistantModeEnabled
                                   ? VoxColors.primary(context)
                                   : VoxColors.onBg(context).withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  provider.isListening
                                      ? Icons.graphic_eq_rounded
                                      : provider.assistantModeEnabled
                                          ? Icons.mic_rounded
                                          : Icons.mic_none_rounded,
                                   color: provider.assistantModeEnabled
                                       ? VoxColors.primary(context)
                                       : VoxColors.textSecondary(context),
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Assistant',
                                  style: TextStyle(
                                    color: provider.assistantModeEnabled
                                        ? VoxColors.primary(context)
                                        : VoxColors.textSecondary(context),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (provider.assistantModeEnabled) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                    color: VoxColors.primary(context),
                                    shape: BoxShape.circle,
                                  ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  lang.t('library'),
                  style: TextStyle(
                    fontSize: 18,
                    color: VoxColors.primary(context), // Vox Blue instead of yellow
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  lang.t('tap_hint'),
                  style: TextStyle(color: VoxColors.textHint(context), fontSize: 11),
                ),
              ],

              // ——— Guest banner ———————————————————————————————————
              if (_isAnonymousUser) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: VoxColors.cardFill(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VoxColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: VoxColors.primary(context), size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Guest mode — files are temporary. Create an account to save them.',
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

              const SizedBox(height: 12),

              // â”€â”€ Folders/Tags â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              SizedBox(
                height: 32,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _folders.length,
                  itemBuilder: (context, index) {
                    final folder = _folders[index];
                    final isSelected = folder == _selectedFolder;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedFolder = folder),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF4B9EFF) : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Center(
                          child: Text(
                            folder,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // â”€â”€ Library content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Expanded(
                child: Consumer<TempLibraryProvider>(
                  builder: (context, tempLibrary, _) {
                    // â”€â”€ Guest: in-memory items â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    if (_isAnonymousUser) {
                      final items = tempLibrary.items
                          .where((item) {
                            final matchesSearch = item.fileName.toLowerCase().contains(_searchQuery);
                            if (!matchesSearch) return false;
                            
                            final t = item.fileType.toLowerCase();
                            if (_selectedFolder == 'All Files') return true;
                            if (_selectedFolder == 'PDFs') return t == 'pdf';
                            if (_selectedFolder == 'Notes') return t == 'note';
                            if (_selectedFolder == 'Scans') return t == 'scan';
                            if (_selectedFolder == 'Documents') return ['doc', 'docx', 'txt', 'ppt', 'pptx', 'csv', 'xls', 'rtf'].contains(t);
                            return true;
                          })
                          .toList();

                      if (items.isEmpty) {
                        _visibleIds = [];
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_off_outlined,
                                color: Colors.grey[400],
                                size: 48,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No files yet.',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap + to upload.\nFiles are temporary until you create an account.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      _visibleIds = items.map((e) => e.id).toList();
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.1,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = _selectedIds.contains(item.id);
                          return GestureDetector(
                            onTap: () {
                              if (_isSelectionMode) {
                                _toggleSelection(item.id);
                              } else {
                                _openReader(item.fileName, item.content);
                              }
                            },
                            onLongPress: () {
                              if (!_isSelectionMode) {
                                _enterSelectionMode(item.id);
                              }
                            },
                            child: _buildFileCard(item.fileName, item.fileType, isSelected: _isSelectionMode && isSelected),
                          );
                        },
                      );
                    }

                    // â”€â”€ Logged in: Firestore filtered by userId â”€â”€
                    if (_resolvedUid == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return StreamBuilder<QuerySnapshot>(
                      // FIX: removed .orderBy() to avoid requiring a composite
                      // Firestore index. Docs are sorted client-side below.
                      stream: FirebaseFirestore.instance
                          .collection('library')
                          .where('userId', isEqualTo: _resolvedUid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          debugPrint('ðŸ”´ Firestore error: ${snapshot.error}');
                          final isOffline = snapshot.error.toString().contains(
                            'unavailable',
                          );
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isOffline
                                      ? Icons.wifi_off
                                      : Icons.error_outline,
                                  color: Colors.grey[500],
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  isOffline
                                      ? 'You\'re offline.\nShowing cached library.'
                                      : 'Something went wrong.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        // Filter by search query AND folder
                        final docs = snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          final name = (data['fileName'] as String? ?? '').toLowerCase();
                          final type = (data['fileType'] as String? ?? '').toLowerCase();
                          
                          if (!name.contains(_searchQuery)) return false;
                          
                          if (_selectedFolder == 'All Files') return true;
                          if (_selectedFolder == 'PDFs') return type == 'pdf';
                          if (_selectedFolder == 'Notes') return type == 'note';
                          if (_selectedFolder == 'Scans') return type == 'scan';
                          if (_selectedFolder == 'Documents') {
                            return ['doc', 'docx', 'txt', 'ppt', 'pptx', 'csv', 'xls', 'rtf'].contains(type);
                          }
                          return true;
                        }).toList();

                        // FIX: sort client-side by timestamp descending
                        // (replaces the removed .orderBy() on the query)
                        docs.sort((a, b) {
                          final aTs =
                              (a.data() as Map<String, dynamic>)['timestamp']
                                  as Timestamp?;
                          final bTs =
                              (b.data() as Map<String, dynamic>)['timestamp']
                                  as Timestamp?;
                          if (aTs == null && bTs == null) return 0;
                          if (aTs == null) return 1;
                          if (bTs == null) return -1;
                          return bTs.compareTo(aTs);
                        });

                        if (docs.isEmpty) {
                          _visibleIds = [];
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 70, height: 70,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4B9EFF).withValues(alpha: 0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.folder_off_outlined, size: 36, color: Colors.white.withValues(alpha: 0.2)),
                                ),
                                const SizedBox(height: 16),
                                Text(lang.t('no_files'),
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontWeight: FontWeight.w700, fontSize: 15)),
                              ],
                            ),
                          );
                        }

                        _visibleIds = docs.map((d) => d.id).toList();
                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.1,
                              ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data =
                                docs[index].data() as Map<String, dynamic>? ??
                                {};
                            final String name =
                                data['fileName'] as String? ?? 'File';
                            final String type =
                                data['fileType'] as String? ?? 'pdf';
                            final String content =
                                data['content'] as String? ?? '';
                            final String docId = docs[index].id;
                            final isSelected = _selectedIds.contains(docId);
                            return GestureDetector(
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(docId);
                                } else {
                                  _openReader(name, content);
                                }
                              },
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  _enterSelectionMode(docId);
                                }
                              },
                              child: _buildFileCard(name, type, isSelected: _isSelectionMode && isSelected),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const MiniPlayerBar(),
            ],
          ),
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
              _navItem(Icons.home, lang.t('nav_home'), Colors.white),
              _navItem(
                Icons.note_alt_outlined,
                lang.t('nav_notes'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/notes'),
              ),
              const SizedBox(width: 48),
              _navItem(
                Icons.book,
                lang.t('nav_dictionary'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/dictionary'),
              ),
              _navItem(
                Icons.menu,
                lang.t('nav_menu'),
                Colors.grey[400]!,
                onTap: () => Navigator.pushNamed(context, '/menu'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF0A0E1A),
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        child: Icon(Icons.file_upload_outlined, color: Colors.white),
      ),
    );
  }

  // â”€â”€ Card count picker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<int?> _pickCardCount(BuildContext context) async {
    int selected = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0A0E1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: const Text(
            'How many questions?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$selected cards',
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
                activeColor: const Color(0xFF4B9EFF),
                inactiveColor: Colors.white.withValues(alpha: 0.1),
                onChanged: (v) => setDialogState(() => selected = v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('5', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                  Text('20', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4B9EFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Generate', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(String title, String type, {bool isSelected = false}) {
    IconData iconData;
    Color iconColor;
    switch (type.toLowerCase()) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        iconColor = Colors.red.shade400;
        break;
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        iconColor = Colors.blue.shade400;
        break;
      case 'ppt':
      case 'pptx':
        iconData = Icons.slideshow;
        iconColor = Colors.orange.shade400;
        break;
      case 'txt':
        iconData = Icons.text_snippet;
        iconColor = Colors.grey.shade600;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey.shade600;
    }
    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4B9EFF).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF4B9EFF) : Colors.white.withValues(alpha: 0.08),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: const Color(0xFF4B9EFF).withValues(alpha: 0.1),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ] : [],
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: isSelected ? 1.0 : 0.7),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(iconData, size: 24, color: iconColor.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ),
        if (isSelected)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF4B9EFF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF4B9EFF).withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1),
                ],
              ),
              child: Icon(Icons.check, color: Colors.white, size: 16),
            ),
          ),
      ],
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
          Icon(icon, color: color == const Color(0xFF0A0E1A) ? Colors.white54 : color, size: 24),
          Text(
            label,
            style: TextStyle(
              color: color == const Color(0xFF0A0E1A) ? Colors.white54 : color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

