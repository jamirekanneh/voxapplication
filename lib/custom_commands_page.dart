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

  // ─────────────────────────────────────────────
  //  RESOLVE USER — identical logic to VoxHomePage
  // ─────────────────────────────────────────────
  Future<void> _resolveUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
      return;
    }

    if (!user.isAnonymous) {
      if (mounted) setState(() { _isAnonymousUser = false; _resolvedUid = user.uid; });
      _loadCommandsForUser(user.uid);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.getBool('hasProfile') ?? false;

    if (!hasProfile) {
      if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
      return;
    }

    final uidDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (uidDoc.exists) {
      if (mounted) setState(() { _isAnonymousUser = false; _resolvedUid = user.uid; });
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
        if (mounted) setState(() { _isAnonymousUser = false; _resolvedUid = docUid; });
        _loadCommandsForUser(docUid);
        return;
      }
    }

    if (mounted) setState(() { _isAnonymousUser = true; _resolvedUid = null; });
  }

  // ─────────────────────────────────────────────
  //  LOAD COMMANDS — keyed by resolvedUid
  // ─────────────────────────────────────────────
  Future<void> _loadCommandsForUser(String uid) async {
    if (!mounted) return;
    final provider = context.read<CustomCommandsProvider>();
    await provider.loadCommandsForUser(uid);
  }

  // ─────────────────────────────────────────────
  //  GUEST LEAVE GUARD
  // ─────────────────────────────────────────────
  Future<bool> _confirmLeave() async {
    if (!_isAnonymousUser) return true;
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Unsaved Data', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        content: const Text(
          'You\'re using a guest account. All voice commands will be lost when you close the app.\n\nCreate an account to save them.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay',
                style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
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

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomCommandsProvider>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3E5AB),
        body: Column(
          children: [
            // ── Header ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 24,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFD4B96A),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: 'Go back',
                    button: true,
                    child: GestureDetector(
                      onTap: () async {
                        if (await _confirmLeave() && mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFFF3E5AB),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Voice Commands',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFF3E5AB),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Double-tap anywhere to activate',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFF3E5AB),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Voice feedback toggle
                  Semantics(
                    label:
                        'Voice feedback ${provider.voiceFeedbackEnabled ? "enabled" : "disabled"}',
                    toggled: provider.voiceFeedbackEnabled,
                    child: GestureDetector(
                      onTap: () => provider
                          .setVoiceFeedback(!provider.voiceFeedbackEnabled),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              provider.voiceFeedbackEnabled
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              color: const Color(0xFFF3E5AB),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              provider.voiceFeedbackEnabled
                                  ? 'Voice feedback: ON'
                                  : 'Voice feedback: OFF',
                              style: const TextStyle(
                                color: Color(0xFFF3E5AB),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Guest banner — matches VoxHomePage style ─────────────────
            if (_isAnonymousUser) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.black.withOpacity(0.1)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.black54, size: 15),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Guest mode — commands are temporary. Create an account to save them.',
                          style: TextStyle(
                              color: Colors.black54,
                              fontSize: 11,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ── Command list ─────────────────────────────
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

        // ── FAB ──────────────────────────────────────
        floatingActionButton: Semantics(
          label: 'Add new voice command',
          button: true,
          child: FloatingActionButton.extended(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            onPressed: () => _showCommandSheet(context),
            icon: const Icon(Icons.add),
            label: const Text(
              'Add Command',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        bottomNavigationBar: BottomAppBar(
          color: Colors.grey[850],
          child: SizedBox(
            height: 65,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(context, Icons.home, 'Home',
                    () => _guardedNav('/home')),
                _navItem(context, Icons.note_alt_outlined, 'Notes',
                    () => _guardedNav('/notes')),
                const SizedBox(width: 48),
                _navItem(context, Icons.book, 'Dictionary',
                    () => _guardedNav('/dictionary')),
                _navItem(context, Icons.menu, 'Menu',
                    () => _guardedNav('/menu')),
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
                color: const Color(0xFFD4B96A).withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                size: 48,
                color: Color(0xFFD4B96A),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No commands yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap "Add Command" to create\nyour first voice command',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label,
      VoidCallback onTap) {
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

// ─────────────────────────────────────────────
//  COMMAND CARD — unchanged from original
// ─────────────────────────────────────────────
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: command.isEnabled
                      ? const Color(0xFFD4B96A).withOpacity(0.2)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  command.action.icon,
                  color: command.isEnabled
                      ? const Color(0xFFD4B96A)
                      : Colors.grey[400],
                  size: 22,
                ),
              ),
              title: Text(
                '"${command.phrase}"',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: command.isEnabled ? Colors.black87 : Colors.black38,
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
                          ? Colors.black54
                          : Colors.black26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (command.parameter != null &&
                      command.parameter!.isNotEmpty)
                    Text(
                      '→ ${command.parameter}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFD4B96A),
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
                              ? const Color(0xFFD4B96A)
                              : Colors.grey[400],
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
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.edit_outlined,
                            color: Colors.black45, size: 20),
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
                        child: Icon(Icons.delete_outline_rounded,
                            color: Colors.redAccent, size: 20),
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
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Command?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text('Remove the command: "${command.phrase}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                context
                    .read<CustomCommandsProvider>()
                    .deleteCommand(command.id);
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  ADD / EDIT BOTTOM SHEET — unchanged from original
// ─────────────────────────────────────────────
void _showCommandSheet(BuildContext context, {CustomCommand? existing}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
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
    _phraseController =
        TextEditingController(text: widget.existing?.phrase ?? '');
    _paramController =
        TextEditingController(text: widget.existing?.parameter ?? '');
    _selectedAction =
        widget.existing?.action ?? CommandActionType.navigateHome;
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
      provider.updateCommand(widget.existing!.copyWith(
        phrase: phrase,
        action: _selectedAction,
        parameter: param,
      ));
    } else {
      provider.addCommand(CustomCommand(
        id: const Uuid().v4(),
        phrase: phrase,
        action: _selectedAction,
        parameter: param,
      ));
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
                  color: Colors.black12,
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
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Voice phrase to say',
              textField: true,
              child: TextField(
                controller: _phraseController,
                decoration: InputDecoration(
                  labelText: 'Phrase to say',
                  hintText: 'e.g. open my notes',
                  prefixIcon: const Icon(Icons.mic_none_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.grey[50],
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
                color: Colors.black38,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Select action for command',
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.grey[50],
                ),
                child: Column(
                  children: CommandActionType.values.map((action) {
                    final isSelected = _selectedAction == action;
                    return Semantics(
                      label: action.displayName,
                      selected: isSelected,
                      button: true,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedAction = action),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFD4B96A).withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                action.icon,
                                size: 18,
                                color: isSelected
                                    ? const Color(0xFFD4B96A)
                                    : Colors.black45,
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
                                        ? Colors.black87
                                        : Colors.black54,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFFD4B96A), size: 18),
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
                  decoration: InputDecoration(
                    labelText: _selectedAction.parameterHint,
                    hintText:
                        _selectedAction == CommandActionType.searchNotes
                            ? 'e.g. chemistry'
                            : 'e.g. Biology Chapter 3',
                    prefixIcon: const Icon(Icons.edit_note_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    filled: true,
                    fillColor: Colors.grey[50],
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
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _save,
                  child: Text(
                    isEditing ? 'Save Changes' : 'Add Command',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
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