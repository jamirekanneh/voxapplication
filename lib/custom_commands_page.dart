import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'custom_commands_provider.dart';

class CustomCommandsPage extends StatefulWidget {
  const CustomCommandsPage({super.key});

  @override
  State<CustomCommandsPage> createState() => _CustomCommandsPageState();
}

class _CustomCommandsPageState extends State<CustomCommandsPage> {
  String? _resolvedUid;
  bool _isAnonymousUser = true;

  @override
  void initState() {
    super.initState();
    _resolveUser();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  RESOLVE USER â€” identical logic to VoxHomePage
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
      _loadCommandsForUser(user.uid);
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
      _loadCommandsForUser(user.uid);
      return;
    }

    // Fallback: look up by saved email (same as VoxHomePage)
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
        _loadCommandsForUser(docUid);
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
  //  LOAD COMMANDS â€” keyed by resolvedUid
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _loadCommandsForUser(String uid) async {
    if (!mounted) return;
    final provider = context.read<CustomCommandsProvider>();
    await provider.loadCommandsForUser(uid);
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  GUEST LEAVE GUARD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<bool> _confirmLeave() async {
    if (!_isAnonymousUser) return true;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Unsaved Data', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'You\'re using a guest account. All voice commands will be lost when you close the app.\n\nCreate an account to save them.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Stay',
              style: TextStyle(
                color: Color(0x8A0A0E1A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave Anyway'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _guardedNav(String route) async {
    if (await _confirmLeave() && mounted) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomCommandsProvider>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final ok = await _confirmLeave();
        if (!context.mounted) return;
        if (ok) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: Column(
          children: [
            // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 24,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Semantics(
                        label: 'Go back',
                        button: true,
                        child: GestureDetector(
                          onTap: () async {
                            if (!mounted) return;
                            final ok = await _confirmLeave();
                            if (!context.mounted) return;
                            if (ok) Navigator.pop(context);
                          },
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const Text(
                        'Personalized Commands',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 20), // Balance the back button
                    ],
                  ),
                  const Text(
                    'Hey Vox! Double-tap anywhere to listen.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4B9EFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Voice feedback toggle
                  Semantics(
                    label:
                        'Voice feedback ${provider.voiceFeedbackEnabled ? "enabled" : "disabled"}',
                    toggled: provider.voiceFeedbackEnabled,
                    child: GestureDetector(
                      onTap: () => provider.setVoiceFeedback(
                        !provider.voiceFeedbackEnabled,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4B9EFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF4B9EFF).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              provider.voiceFeedbackEnabled
                                  ? Icons.record_voice_over_rounded
                                  : Icons.voice_over_off_rounded,
                              color: const Color(0xFF4B9EFF),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              provider.voiceFeedbackEnabled
                                  ? 'Voice Responses: ON'
                                  : 'Voice Responses: OFF',
                              style: const TextStyle(
                                color: Color(0xFF4B9EFF),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            // â”€â”€ Guest banner â€” matches VoxHomePage style â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (_isAnonymousUser) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Color(0xFF0A0E1A).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Color(0xFF0A0E1A).withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Color(0x8A0A0E1A),
                        size: 15,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Guest mode â€” commands are temporary. Create an account to save them.',
                          style: TextStyle(
                            color: Color(0x8A0A0E1A),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // â”€â”€ Command list â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Expanded(
              child: _resolvedUid == null && !_isAnonymousUser
                  ? const Center(child: CircularProgressIndicator())
                  : provider.commands.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.commands.length,
                      itemBuilder: (_, i) =>
                          _CommandCard(command: provider.commands[i]),
                    ),
            ),
          ],
        ),

        // â”€â”€ Google Assistant / Siri Style Orb â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        floatingActionButton: Semantics(
          label: 'Add new voice command',
          button: true,
          child: GestureDetector(
            onTap: () => _showCommandSheet(context),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4B9EFF),
                    Color(0xFF9028F5),
                    Color(0xFF4B9EFF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4B9EFF).withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: const Color.fromARGB(
                      255,
                      25,
                      17,
                      67,
                    ).withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 32),
            ),
          ),
        ),

        bottomNavigationBar: BottomAppBar(
          color: const Color(0xFF141A29),
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: SizedBox(
            height: 65,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(
                  context,
                  Icons.home,
                  'Home',
                  () => _guardedNav('/home'),
                ),
                _navItem(
                  context,
                  Icons.note_alt_outlined,
                  'Notes',
                  () => _guardedNav('/notes'),
                ),
                const SizedBox(width: 48),
                _navItem(
                  context,
                  Icons.book,
                  'Dictionary',
                  () => _guardedNav('/dictionary'),
                ),
                _navItem(
                  context,
                  Icons.menu,
                  'Menu',
                  () => _guardedNav('/menu'),
                ),
              ],
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'No voice commands yet. Tap Add Command to create one.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF4B9EFF).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                size: 48,
                color: Color(0xFF4B9EFF),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No personalized commands',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the glowing orb to create\nyour first voice command',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey[400], size: 24),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  COMMAND CARD â€” unchanged from original
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _CommandCard extends StatelessWidget {
  final CustomCommand command;
  const _CommandCard({required this.command});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CustomCommandsProvider>();

    return Semantics(
      label:
          'Command: say "${command.phrase}" to ${command.action.displayName}. ${command.isEnabled ? "Enabled" : "Disabled"}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: command.isEnabled
                      ? const Color(0xFF4B9EFF).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  command.action.icon,
                  color: command.isEnabled
                      ? const Color(0xFF4B9EFF)
                      : Colors.white.withValues(alpha: 0.3),
                  size: 22,
                ),
              ),
              title: Text(
                '"${command.phrase}"',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: command.isEnabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  fontStyle: FontStyle.italic,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    command.action.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: command.isEnabled
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.3),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (command.parameter != null &&
                      command.parameter!.isNotEmpty)
                    Text(
                      'â†’ ${command.parameter}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4B9EFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: command.isEnabled
                        ? 'Disable command'
                        : 'Enable command',
                    button: true,
                    child: GestureDetector(
                      onTap: () => provider.toggleCommand(command.id),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          command.isEnabled
                              ? Icons.toggle_on_rounded
                              : Icons.toggle_off_rounded,
                          color: command.isEnabled
                              ? const Color(0xFF4B9EFF)
                              : Colors.white.withValues(alpha: 0.3),
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Edit command',
                    button: true,
                    child: GestureDetector(
                      onTap: () =>
                          _showCommandSheet(context, existing: command),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.edit_outlined,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Delete command',
                    button: true,
                    child: GestureDetector(
                      onTap: () => _confirmDelete(context, command),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
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
    );
  }

  void _confirmDelete(BuildContext context, CustomCommand command) {
    showDialog(
      context: context,
      builder: (ctx) => Semantics(
        label: 'Delete command confirmation dialog',
        child: AlertDialog(
          backgroundColor: const Color(0xFF0A0E1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: const Text(
            'Delete Command?',
            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
          ),
          content: Text(
            'Remove the command: "${command.phrase}"?\n\nThis item will be stored in the Recycle Bin and permanently deleted after 30 days.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final curUid = FirebaseAuth.instance.currentUser?.uid;
                if (curUid != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(curUid)
                      .collection('deleted_library')
                      .add({
                        'fileName': 'Command: ${command.phrase}',
                        'phrase': command.phrase,
                        'action': command.action.name,
                        'parameter': command.parameter,
                        'isEnabled': command.isEnabled,
                        'fileType': 'command',
                        'sourceCollection': 'custom_commands',
                        'commandId': command.id,
                        'deletedAt': FieldValue.serverTimestamp(),
                        'originalTimestamp': FieldValue.serverTimestamp(),
                        'userId': curUid,
                      });
                }
                if (ctx.mounted) {
                  ctx.read<CustomCommandsProvider>().deleteCommand(command.id);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  ADD / EDIT BOTTOM SHEET â€” unchanged from original
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
void _showCommandSheet(BuildContext context, {CustomCommand? existing}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0A0E1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _CommandSheet(existing: existing),
  );
}

class _CommandSheet extends StatefulWidget {
  final CustomCommand? existing;
  const _CommandSheet({this.existing});

  @override
  State<_CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends State<_CommandSheet> {
  late TextEditingController _phraseController;
  late TextEditingController _paramController;
  late CommandActionType _selectedAction;

  @override
  void initState() {
    super.initState();
    _phraseController = TextEditingController(
      text: widget.existing?.phrase ?? '',
    );
    _paramController = TextEditingController(
      text: widget.existing?.parameter ?? '',
    );
    _selectedAction = widget.existing?.action ?? CommandActionType.navigateHome;
  }

  @override
  void dispose() {
    _phraseController.dispose();
    _paramController.dispose();
    super.dispose();
  }

  void _save() {
    final phrase = _phraseController.text.trim();
    if (phrase.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a phrase'),
          backgroundColor: Color(0xFF333333),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final provider = context.read<CustomCommandsProvider>();
    final param = _selectedAction.requiresParameter
        ? _paramController.text.trim()
        : null;

    if (widget.existing != null) {
      provider.updateCommand(
        widget.existing!.copyWith(
          phrase: phrase,
          action: _selectedAction,
          parameter: param,
        ),
      );
    } else {
      provider.addCommand(
        CustomCommand(
          id: const Uuid().v4(),
          phrase: phrase,
          action: _selectedAction,
          parameter: param,
        ),
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEditing ? 'Edit Command' : 'New Command',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Voice phrase to say',
              textField: true,
              child: TextField(
                controller: _phraseController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Phrase to say',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  hintText: 'e.g. open my notes',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  prefixIcon: Icon(
                    Icons.mic_none_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                ),
                textCapitalization: TextCapitalization.none,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'ACTION',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Select action for command',
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.04),
                ),
                child: Column(
                  children: CommandActionType.values.map((action) {
                    final isSelected = _selectedAction == action;
                    return Semantics(
                      label: action.displayName,
                      selected: isSelected,
                      button: true,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedAction = action),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF4B9EFF).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                action.icon,
                                size: 18,
                                color: isSelected
                                    ? const Color(0xFF4B9EFF)
                                    : Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  action.displayName,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.6),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF4B9EFF),
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_selectedAction.requiresParameter) ...[
              const SizedBox(height: 16),
              Semantics(
                label: _selectedAction.parameterHint,
                textField: true,
                child: TextField(
                  controller: _paramController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: _selectedAction.parameterHint,
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    hintText: _selectedAction == CommandActionType.searchNotes
                        ? 'e.g. chemistry'
                        : 'e.g. Biology Chapter 3',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    prefixIcon: Icon(
                      Icons.edit_note_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Semantics(
              label: isEditing ? 'Save changes' : 'Add command',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4B9EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _save,
                  child: Text(
                    isEditing ? 'Save Changes' : 'Add Command',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

