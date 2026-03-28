import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'language_provider.dart';
import 'tts_service.dart';
import 'reader_page.dart';

// ════════════════════════════════════════════════════════════
//  DELETED FILES PAGE
//  • Soft-deleted files live in: users/{uid}/deleted_library
//  • [resolvedUid] must be passed — it is the Firestore document
//    UID for the user (may differ from Firebase Auth UID for
//    anonymous-auth users who signed up by email form).
//  • Restore  → moves doc back to top-level library collection
//  • Open     → previews in reader without restoring
//  • Perm delete → removes from bin forever
//  • Empty bin → wipes all docs in deleted_library
// ════════════════════════════════════════════════════════════
class DeletedFilesPage extends StatelessWidget {
  /// The resolved Firestore UID — pass _resolvedUid from home_page.
  /// Falls back to FirebaseAuth.instance.currentUser!.uid if null.
  final String? resolvedUid;
  const DeletedFilesPage({super.key, this.resolvedUid});

  String get _uid => resolvedUid ?? FirebaseAuth.instance.currentUser!.uid;

  // ── Bin collection reference ───────────────────────────────
  CollectionReference get _bin => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('deleted_library');

  // ── Restore file back to library ──────────────────────────
  Future<void> _restore(BuildContext context, DocumentSnapshot doc) async {
    try {
      final data = Map<String, dynamic>.from(
        doc.data() as Map<String, dynamic>,
      );
      data.remove('deletedAt');

      final sourceCol = data['sourceCollection'] as String?;
      final isNote = sourceCol == 'notes';

      if (isNote) {
        data['title'] = data['fileName'];
        data.remove('fileName');
        data.remove('sourceCollection');
        data.remove('fileType');
      }

      // Make sure userId is set correctly in restored doc
      data['userId'] = _uid;
      data['timestamp'] =
          data['originalTimestamp'] ?? FieldValue.serverTimestamp();
      data.remove('originalTimestamp');

      final targetCollection = isNote ? 'notes' : 'library';
      await FirebaseFirestore.instance.collection(targetCollection).add(data);
      await _bin.doc(doc.id).delete();

      if (context.mounted) {
        final itemName = isNote ? data['title'] : data['fileName'];
        final destName = isNote ? 'notes' : 'library';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$itemName" restored to $destName.'),
            backgroundColor: const Color(0xFF333333),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restore failed. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Open in reader (preview without restoring) ─────────────
  void _openReader(BuildContext context, String fileName, String content) {
    final locale = context.read<LanguageProvider>().ttsLocale;
    final ttsService = context.read<TtsService>();
    final langProvider = context.read<LanguageProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: ttsService),
            ChangeNotifierProvider.value(value: langProvider),
          ],
          child: ReaderPage(title: fileName, content: content, locale: locale),
        ),
      ),
    );
  }

  // ── Permanently delete one file ────────────────────────────
  Future<void> _permanentDelete(
    BuildContext context,
    DocumentSnapshot doc,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['fileName'] as String? ?? 'File';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete permanently?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          '"$name" will be gone forever.',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _bin.doc(doc.id).delete();
  }

  // ── Empty entire bin ───────────────────────────────────────
  Future<void> _emptyBin(
    BuildContext context,
    List<DocumentSnapshot> docs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Empty bin?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('All deleted files will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Empty', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final d in docs) {
        await _bin.doc(d.id).delete();
      }
    }
  }

  // ── Icon & colour helpers ──────────────────────────────────
  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'epub':
        return Icons.menu_book;
      case 'scan':
        return Icons.document_scanner_rounded;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade400;
      case 'doc':
      case 'docx':
        return Colors.blue.shade400;
      case 'ppt':
      case 'pptx':
        return Colors.orange.shade400;
      case 'xls':
      case 'xlsx':
        return Colors.green.shade400;
      case 'epub':
        return Colors.purple.shade400;
      case 'scan':
        return Colors.teal.shade400;
      default:
        return Colors.grey.shade500;
    }
  }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB),
      appBar: AppBar(
        title: const Text(
          'Deleted Files',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // Empty bin button — only visible when bin has items
          StreamBuilder<QuerySnapshot>(
            stream: _bin.snapshots(),
            builder: (_, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton.icon(
                onPressed: () => _emptyBin(context, snap.data!.docs),
                icon: const Icon(
                  Icons.delete_sweep,
                  color: Colors.redAccent,
                  size: 18,
                ),
                label: const Text(
                  'Empty bin',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _bin.orderBy('deletedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Fallback without ordering if index not ready
            return StreamBuilder<QuerySnapshot>(
              stream: _bin.snapshots(),
              builder: (context, snap2) {
                if (!snap2.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.black),
                  );
                }
                return _buildList(context, snap2.data!.docs);
              },
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );
          }
          return _buildList(context, snapshot.data!.docs);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<DocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 72, color: Colors.grey[350]),
            const SizedBox(height: 16),
            Text(
              'Bin is empty',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Deleted files appear here.\nYou can restore or remove them forever.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final data = doc.data() as Map<String, dynamic>;
        final name = data['fileName'] as String? ?? 'Unknown';
        final type = data['fileType'] as String? ?? 'file';
        final content = data['content'] as String? ?? '';
        final deletedAt = data['deletedAt'];

        String dateStr = '';
        if (deletedAt is Timestamp) {
          final dt = deletedAt.toDate();
          dateStr =
              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            // Tap to preview in reader
            onTap: content.isNotEmpty
                ? () => _openReader(context, name, content)
                : null,
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _colorForType(type).withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _iconForType(type),
                color: _colorForType(type),
                size: 24,
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dateStr.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Deleted $dateStr',
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                ],
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Tap to preview',
                    style: TextStyle(
                      color: Colors.grey[350],
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Restore ──────────────────────────────
                Tooltip(
                  message: 'Restore to library',
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4B96A).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.restore_rounded,
                        color: Color(0xFFB8952A),
                        size: 20,
                      ),
                      onPressed: () => _restore(context, doc),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // ── Permanent delete ──────────────────────
                Tooltip(
                  message: 'Delete permanently',
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () => _permanentDelete(context, doc),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
