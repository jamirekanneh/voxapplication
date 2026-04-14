import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  String? _resolvedUid;
  bool _isGuest = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveUser().then((_) {
      if (!_isGuest && _resolvedUid != null) {
        _cleanUpExpiredItems();
      }
    });
  }

  Future<void> _resolveUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) setState(() { _isGuest = true; _loading = false; });
      return;
    }

    if (!user.isAnonymous) {
      if (mounted) setState(() { _isGuest = false; _resolvedUid = user.uid; _loading = false; });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasProfile = prefs.getBool('hasProfile') ?? false;
    if (!hasProfile) {
      if (mounted) setState(() { _isGuest = true; _loading = false; });
      return;
    }

    final uidDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (uidDoc.exists) {
      if (mounted) setState(() { _isGuest = false; _resolvedUid = user.uid; _loading = false; });
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
        if (mounted) setState(() { _isGuest = false; _resolvedUid = query.docs.first.id; _loading = false; });
        return;
      }
    }

    if (mounted) setState(() { _isGuest = true; _loading = false; });
  }

  CollectionReference get _bin => FirebaseFirestore.instance
      .collection('users')
      .doc(_resolvedUid)
      .collection('deleted_library');

  // ─────────────────────────────────────────────
  //  RESTORE
  // ─────────────────────────────────────────────
  Future<void> _restore(BuildContext context, DocumentSnapshot doc) async {
    try {
      final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      final sourceCol = data['sourceCollection'] as String? ?? 'library';
      final itemName = data['fileName'] as String? ?? data['phrase'] as String? ?? 'Item';

      data.remove('deletedAt');
      data.remove('sourceCollection');

      if (sourceCol == 'notes') {
        // Restore as a note
        final noteData = {
          'title': data['fileName'] ?? 'Note',
          'content': data['content'] ?? '',
          'audioUrl': data['audioUrl'],
          'recordingDurationSeconds': data['recordingDurationSeconds'],
          'userId': _resolvedUid,
          'timestamp': data['originalTimestamp'] ?? FieldValue.serverTimestamp(),
        };
        noteData.removeWhere((_, v) => v == null);
        await FirebaseFirestore.instance.collection('notes').add(noteData);

      } else if (sourceCol == 'custom_commands') {
        // Restore as a custom command
        final cmdData = {
          'id': data['commandId'] ?? doc.id,
          'phrase': data['phrase'] ?? '',
          'action': data['action'] ?? 'navigateHome',
          'parameter': data['parameter'],
          'isEnabled': data['isEnabled'] ?? true,
          'userId': _resolvedUid,
        };
        cmdData.removeWhere((_, v) => v == null);
        await FirebaseFirestore.instance.collection('custom_commands').add(cmdData);

      } else {
        // Restore as a library file
        final libData = {
          'fileName': data['fileName'] ?? 'File',
          'content': data['content'] ?? '',
          'fileType': data['fileType'] ?? 'file',
          'userId': _resolvedUid,
          'timestamp': data['originalTimestamp'] ?? FieldValue.serverTimestamp(),
        };
        libData.removeWhere((_, v) => v == null);
        await FirebaseFirestore.instance.collection('library').add(libData);
      }

      await _bin.doc(doc.id).delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text('"$itemName" restored successfully.')),
              ],
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Restore failed. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  PERMANENT DELETE
  // ─────────────────────────────────────────────
  Future<void> _permanentDelete(BuildContext context, DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['fileName'] as String? ?? data['phrase'] as String? ?? 'Item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Forever?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Text('"$name" will be permanently deleted and cannot be recovered.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0x8A0A0E1A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _bin.doc(doc.id).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" permanently deleted.'),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  EMPTY TRASH
  // ─────────────────────────────────────────────
  Future<void> _emptyTrash(BuildContext context, List<DocumentSnapshot> docs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Empty Trash?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Text('All ${docs.length} item(s) will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0x8A0A0E1A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('Trash emptied successfully.'),
              ],
            ),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────
  int _daysRemaining(dynamic deletedAt) {
    if (deletedAt == null) return 30;
    DateTime deletedDate;
    if (deletedAt is Timestamp) {
      deletedDate = deletedAt.toDate();
    } else {
      return 30;
    }
    final expiry = deletedDate.add(const Duration(days: 30));
    final remaining = expiry.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining;
  }

  IconData _iconForType(String? fileType, String? sourceCol) {
    if (sourceCol == 'notes') return Icons.note_alt_outlined;
    if (sourceCol == 'custom_commands') return Icons.mic_none_rounded;
    switch (fileType?.toLowerCase()) {
      case 'pdf': return Icons.picture_as_pdf_outlined;
      case 'docx': case 'doc': return Icons.description_outlined;
      case 'pptx': case 'ppt': return Icons.slideshow_outlined;
      case 'scan': return Icons.document_scanner_outlined;
      case 'txt': case 'md': return Icons.article_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorForType(String? sourceCol) {
    if (sourceCol == 'notes') return const Color(0xFF5C8AFF);
    if (sourceCol == 'custom_commands') return const Color(0xFF9B59B6);
    return const Color(0xFF4B9EFF);
  }

  String _typeLabel(String? fileType, String? sourceCol) {
    if (sourceCol == 'notes') return 'Note';
    if (sourceCol == 'custom_commands') return 'Command';
    return (fileType ?? 'file').toUpperCase();
  }

  // ─────────────────────────────────────────────
  //  AUTO DELETE EXPIRED ITEMS
  // ─────────────────────────────────────────────
  Future<void> _cleanUpExpiredItems() async {
    if (_resolvedUid == null) return;
    final thirtyDaysAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
    
    try {
      final expiredQuery = await _bin.where('deletedAt', isLessThanOrEqualTo: thirtyDaysAgo).get();
      if (expiredQuery.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in expiredQuery.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Items Auto-Deleted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Text('${expiredQuery.docs.length} item(s) were permanently deleted because they have been in the Recycle Bin for more than 30 days.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(color: Color(0xFF0A0E1A))),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to cleanup expired items: $e');
    }
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF0F4FF),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // ── Guest Guard ──────────────────────────────
    if (_isGuest) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          title: const Text('Recycle Bin', style: TextStyle(color: Color(0xFF0A0E1A), fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF0A0E1A)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Color(0xFF0A0E1A).withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.delete_outline_rounded, size: 52, color: Colors.grey[500]),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recycle Bin Unavailable',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'The Recycle Bin is a feature for registered users only.\n\nGuest data is temporary and is permanently removed when you leave the app. Create an account to unlock 30-day recovery of deleted items.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.6),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Logged-in User View ──────────────────────
    final thirtyDaysAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          title: const Text('Recycle Bin', style: TextStyle(color: Color(0xFF0A0E1A), fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFF0A0E1A)),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Color(0xFF0A0E1A),
            unselectedLabelColor: Color(0x8A0A0E1A),
            indicatorColor: Color(0xFF0A0E1A),
            tabs: [
              Tab(text: 'Notes'),
              Tab(text: 'Recordings'),
              Tab(text: 'Uploads'),
              Tab(text: 'Commands'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _bin
              .where('deletedAt', isGreaterThan: thirtyDaysAgo)
              .orderBy('deletedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Something went wrong.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600])),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            // Categorize
            final notesDocs = docs.where((d) {
              final val = d.data() as Map<String, dynamic>;
              return val['sourceCollection'] == 'notes' && val['audioUrl'] == null;
            }).toList();
            
            final recordingsDocs = docs.where((d) {
              final val = d.data() as Map<String, dynamic>;
              return val['sourceCollection'] == 'recordings' || (val['sourceCollection'] == 'notes' && val['audioUrl'] != null);
            }).toList();

            final uploadsDocs = docs.where((d) {
              final val = d.data() as Map<String, dynamic>;
              return val['sourceCollection'] == 'library';
            }).toList();

            final commandsDocs = docs.where((d) {
              final val = d.data() as Map<String, dynamic>;
              return val['sourceCollection'] == 'custom_commands';
            }).toList();

            return Column(
              children: [
                // Info banner
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Color(0xFF0A0E1A).withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 15, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Items are permanently deleted after 30 days.',
                            style: TextStyle(fontSize: 11, color: Colors.grey[700], height: 1.4),
                          ),
                        ),
                        if (docs.isNotEmpty)
                          GestureDetector(
                            onTap: () => _emptyTrash(context, docs),
                            child: const Text('Empty Trash',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildList(notesDocs),
                      _buildList(recordingsDocs),
                      _buildList(uploadsDocs),
                      _buildList(commandsDocs),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(List<DocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Color(0xFF0A0E1A).withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.description_outlined, size: 40, color: Colors.grey[400]),
            ),
            const SizedBox(height: 16),
            const Text('No deleted files here',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0x8A0A0E1A))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final sourceCol = data['sourceCollection'] as String?;
        final fileType = data['fileType'] as String?;
        final name = data['fileName'] as String? ?? data['phrase'] as String? ?? 'Unknown';
        final daysLeft = _daysRemaining(data['deletedAt']);
        final typeColor = _colorForType(sourceCol);
        final typeIcon = _iconForType(fileType, sourceCol);
        final typeLabel = _typeLabel(fileType, sourceCol);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF0A0E1A).withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 24),
                ),
                const SizedBox(width: 14),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(typeLabel,
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: typeColor)),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.timer_outlined,
                            size: 11,
                            color: daysLeft <= 3 ? Colors.redAccent : Colors.grey[500],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            daysLeft == 0
                                ? 'Expires today'
                                : 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: daysLeft <= 3 ? Colors.redAccent : Colors.grey[500],
                              fontWeight: daysLeft <= 3 ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Actions
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _restore(context, doc),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restore_rounded, color: Color(0xFF2E7D32), size: 15),
                            SizedBox(width: 4),
                            Text('Restore', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _permanentDelete(context, doc),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 15),
                            SizedBox(width: 4),
                            Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
