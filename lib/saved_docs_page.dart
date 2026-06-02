import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'ai_service.dart';
import 'language_provider.dart';
import 'pdf_service.dart';
import 'services/app_session.dart';
import 'services/auth_session.dart';
import 'widgets/firestore_data_gate.dart';
import 'services/saved_docs_export_service.dart';
import 'services/saved_docs_service.dart';
import 'theme_provider.dart';

class SavedDocsPage extends StatefulWidget {
  const SavedDocsPage({super.key});

  @override
  State<SavedDocsPage> createState() => _SavedDocsPageState();
}

class _SavedDocsPageState extends State<SavedDocsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _uid;
  bool _loadingUser = true;
  bool _isGuest = true;
  bool _exporting = false;
  List<SavedDocEntry> _cachedMerged = [];

  @override
  void initState() {
    super.initState();
    final bootUid = AppSession.bootstrapUid;
    if (bootUid != null) {
      _uid = bootUid;
      _isGuest = false;
      _loadingUser = false;
    }
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _resolveUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _resolveUser() async {
    final session = await AuthSession.resolveForApp();
    if (!mounted) return;
    final nextGuest = session.guest;
    final nextUid = nextGuest ? null : (session.uid ?? _uid);
    if (nextGuest == _isGuest && nextUid == _uid && !_loadingUser) return;
    setState(() {
      _isGuest = nextGuest;
      _uid = nextUid;
      _loadingUser = false;
    });
  }

  List<SavedDocEntry> _mapDocs(
    QuerySnapshot<Map<String, dynamic>> snap, {
    bool legacy = false,
  }) {
    return snap.docs.map((doc) {
      final data = doc.data();
      if (legacy) {
        return SavedDocEntry(
          id: doc.id,
          legacy: true,
          type: SavedDocsService.typeQa,
          title: (data['documentTitle'] as String?)?.trim() ?? 'Untitled Q&A',
          source: data['source'] as String? ?? 'Home',
          createdAt: data['createdAt'] as Timestamp?,
          data: data,
        );
      }
      return SavedDocEntry(
        id: doc.id,
        legacy: false,
        type: data['type'] as String? ?? SavedDocsService.typeQa,
        title: (data['title'] as String?)?.trim() ?? 'Untitled',
        source: data['source'] as String? ?? 'Home',
        createdAt: data['createdAt'] as Timestamp?,
        data: data,
      );
    }).toList();
  }

  List<SavedDocEntry> _mergeAndSort(
    List<SavedDocEntry> a,
    List<SavedDocEntry> b,
  ) {
    final all = [...a, ...b];
    all.sort((x, y) {
      final xt = x.createdAt;
      final yt = y.createdAt;
      if (xt == null && yt == null) return 0;
      if (xt == null) return 1;
      if (yt == null) return -1;
      return yt.compareTo(xt);
    });
    return all;
  }

  List<SavedDocEntry> _filterEntries(List<SavedDocEntry> entries, int tabIndex) {
    Iterable<SavedDocEntry> list = entries;
    switch (tabIndex) {
      case 1:
        list = list.where((e) => e.type == SavedDocsService.typeSummary);
        break;
      case 2:
        list = list.where((e) => e.type == SavedDocsService.typeQa);
        break;
      case 3:
        list = list.where((e) => e.type == SavedDocsService.typeNote);
        break;
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((e) => e.title.toLowerCase().contains(_searchQuery));
    }
    return list.toList();
  }

  void _openEntry(SavedDocEntry entry) {
    switch (entry.type) {
      case SavedDocsService.typeSummary:
        final content = entry.data['content'] as String? ?? '';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SavedSummaryViewer(
              title: entry.title,
              content: content,
            ),
          ),
        );
        break;
      case SavedDocsService.typeNote:
        final content = entry.data['content'] as String? ?? '';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _SavedNoteViewer(
              title: entry.title,
              content: content,
            ),
          ),
        );
        break;
      case SavedDocsService.typeQa:
      default:
        final questionsList = entry.data['questions'] as List<dynamic>?;
        if (questionsList == null) return;
        final flashcards = questionsList.map((e) {
          final m = e as Map<String, dynamic>;
          return Flashcard(
            question: m['question']?.toString() ?? '',
            answer: m['answer']?.toString() ?? '',
          );
        }).toList();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AssessmentViewerScreen(
              title: entry.title,
              flashcards: flashcards,
            ),
          ),
        );
    }
  }

  Future<void> _bulkExportVisible() async {
    final lang = context.read<LanguageProvider>();
    final toExport = _filterEntries(_cachedMerged, _tabController.index);
    if (toExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.t('bulk_export_empty'))),
      );
      return;
    }

    final tabName = switch (_tabController.index) {
      1 => lang.t('saved_docs_tab_summaries'),
      2 => lang.t('saved_docs_tab_qa'),
      3 => lang.t('saved_docs_tab_notes'),
      _ => lang.t('saved_docs_tab_all'),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.t('bulk_export_saved_docs')),
        content: Text(
          lang.tNamed('bulk_export_confirm', {
            'count': '${toExport.length}',
            'tab': tabName,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.t('bulk_export_saved_docs')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _exporting = true);
    final path = await SavedDocsExportService.exportToZip(context, toExport);
    if (!mounted) return;
    setState(() => _exporting = false);

    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.tNamed('bulk_export_done', {'path': path})),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.t('bulk_export_failed'))),
      );
    }
  }

  Future<void> _confirmDelete(SavedDocEntry entry) async {
    final lang = context.read<LanguageProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VoxColors.surface(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          lang.t('delete_saved_doc_title'),
          style: TextStyle(
            color: VoxColors.onSurface(ctx),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          lang.tNamed('delete_saved_doc_body', {'title': entry.title}),
          style: TextStyle(color: VoxColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.t('cancel'), style: TextStyle(color: VoxColors.textHint(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: VoxColors.danger),
            child: Text(lang.t('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || _uid == null) return;
    await SavedDocsService.deleteDoc(
      uid: _uid!,
      docId: entry.id,
      legacy: entry.legacy,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.t('saved_doc_deleted')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _typeBadge(SavedDocEntry entry) {
    final (label, icon, color) = switch (entry.type) {
      SavedDocsService.typeSummary => ('Summary', Icons.summarize_outlined, Colors.teal),
      SavedDocsService.typeNote => ('Note', Icons.note_alt_outlined, VoxColors.accent(context)),
      _ => ('Q&A', Icons.style_outlined, VoxColors.primary(context)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceBadge(String source) {
    final isHome = source == 'Home';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHome
            ? VoxColors.primary(context).withValues(alpha: 0.1)
            : VoxColors.accent(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isHome ? VoxColors.primary(context) : VoxColors.accent(context),
        ),
      ),
    );
  }

  Widget _buildList(List<SavedDocEntry> entries) {
    final lang = context.read<LanguageProvider>();
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open_outlined,
                  size: 48, color: VoxColors.textHint(context)),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? lang.t('no_saved_docs_yet')
                    : lang.t('no_saved_docs_match'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: VoxColors.textSecondary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final timestamp = entry.createdAt?.toDate();
        final dateStr = timestamp != null
            ? '${timestamp.day}/${timestamp.month}/${timestamp.year}'
            : '—';
        final meta = entry.type == SavedDocsService.typeQa
            ? '${(entry.data['questions'] as List?)?.length ?? 0} cards'
            : entry.type == SavedDocsService.typeNote
                ? lang.t('saved_doc_note')
                : lang.t('saved_doc_summary');

        return GestureDetector(
          onTap: () => _openEntry(entry),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: VoxColors.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VoxColors.border(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: VoxColors.primary(context).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      entry.type == SavedDocsService.typeSummary
                          ? Icons.summarize_outlined
                          : entry.type == SavedDocsService.typeNote
                              ? Icons.note_alt_outlined
                              : Icons.style_outlined,
                      color: VoxColors.primary(context),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: VoxColors.onSurface(context),
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _typeBadge(entry),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(meta,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: VoxColors.textHint(context))),
                            const SizedBox(width: 8),
                            _sourceBadge(entry.source),
                            const SizedBox(width: 8),
                            Text(dateStr,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: VoxColors.textHint(context))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: VoxColors.danger, size: 20),
                    onPressed: () => _confirmDelete(entry),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();

    if (_loadingUser) {
      return Scaffold(
        backgroundColor: VoxColors.bg(context),
        body: Center(
          child: CircularProgressIndicator(color: VoxColors.primary(context)),
        ),
      );
    }

    if (_isGuest || _uid == null) {
      return Scaffold(
        backgroundColor: VoxColors.bg(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: VoxColors.onBg(context)),
          title: Text(
            lang.t('menu_saved_docs'),
            style: TextStyle(
              color: VoxColors.onBg(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded,
                    color: VoxColors.primary(context), size: 42),
                const SizedBox(height: 16),
                Text(
                  lang.t('sign_in_required'),
                  style: TextStyle(
                    color: VoxColors.onBg(context),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  lang.t('saved_docs_sign_in_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VoxColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final uid = _uid!;

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        title: Text(
          lang.t('menu_saved_docs'),
          style: TextStyle(
            color: VoxColors.onBg(context),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: VoxColors.onBg(context)),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_for_offline_outlined),
              tooltip: lang.t('bulk_export_saved_docs'),
              onPressed: _cachedMerged.isEmpty ? null : _bulkExportVisible,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: VoxColors.onBg(context),
          unselectedLabelColor: VoxColors.textSecondary(context),
          indicatorColor: VoxColors.primary(context),
          tabs: [
            Tab(text: lang.t('saved_docs_tab_all')),
            Tab(text: lang.t('saved_docs_tab_summaries')),
            Tab(text: lang.t('saved_docs_tab_qa')),
            Tab(text: lang.t('saved_docs_tab_notes')),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: lang.t('search_by_title'),
                prefixIcon: Icon(Icons.search, color: VoxColors.textHint(context)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: VoxColors.surface(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: VoxColors.border(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: VoxColors.border(context)),
                ),
              ),
            ),
          ),
          Expanded(
            child: FirestoreDataGate(
              userId: uid,
              builder: (context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey('saved_docs_$uid'),
                stream: SavedDocsService.watchUserDocs(uid),
                builder: (context, newSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: SavedDocsService.watchLegacyAssessments(uid),
                    builder: (context, legacySnap) {
                    if (newSnap.hasError &&
                        firestoreSnapshotDenied(newSnap.error, uid)) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: VoxColors.primary(context),
                        ),
                      );
                    }
                    if (legacySnap.hasError &&
                        firestoreSnapshotDenied(legacySnap.error, uid)) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: VoxColors.primary(context),
                        ),
                      );
                    }
                    if (!newSnap.hasData && !legacySnap.hasData) {
                      if (newSnap.connectionState == ConnectionState.waiting ||
                          legacySnap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: VoxColors.primary(context),
                          ),
                        );
                      }
                    }
                    final merged = _mergeAndSort(
                      newSnap.hasData
                          ? _mapDocs(newSnap.data!)
                          : <SavedDocEntry>[],
                      legacySnap.hasData
                          ? _mapDocs(legacySnap.data!, legacy: true)
                          : <SavedDocEntry>[],
                    );
                    _cachedMerged = merged;
                    return TabBarView(
                      controller: _tabController,
                      children: List.generate(
                        4,
                        (i) => _buildList(_filterEntries(merged, i)),
                      ),
                    );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSummaryViewer extends StatelessWidget {
  final String title;
  final String content;

  const _SavedSummaryViewer({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LanguageProvider>();
    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: VoxColors.onBg(context)),
        title: Text(title, style: TextStyle(color: VoxColors.onBg(context))),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () =>
                PdfService.exportSummaryPdf(context, title, content),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () =>
                PdfService.exportTextFile(context, title, content, 'Summary'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            content,
            style: TextStyle(
              color: VoxColors.onBg(context),
              fontSize: 15,
              height: 1.65,
            ),
          ),
          if (content.trim().isEmpty)
            Text(lang.t('no_content'),
                style: TextStyle(color: VoxColors.textHint(context))),
        ],
      ),
    );
  }
}

class _SavedNoteViewer extends StatelessWidget {
  final String title;
  final String content;

  const _SavedNoteViewer({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: VoxColors.onBg(context)),
        title: Text(title, style: TextStyle(color: VoxColors.onBg(context))),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () =>
                PdfService.exportTextFile(context, title, content, 'Note'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            content,
            style: TextStyle(
              color: VoxColors.onBg(context),
              fontSize: 15,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Q&A flashcard viewer (reused from previous saved assessments page) ──
class AssessmentViewerScreen extends StatefulWidget {
  final String title;
  final List<Flashcard> flashcards;

  const AssessmentViewerScreen({
    super.key,
    required this.title,
    required this.flashcards,
  });

  @override
  State<AssessmentViewerScreen> createState() => _AssessmentViewerScreenState();
}

class _AssessmentViewerScreenState extends State<AssessmentViewerScreen> {
  int _currentCard = 0;
  late List<bool> _flipped;

  @override
  void initState() {
    super.initState();
    _flipped = List.filled(widget.flashcards.length, false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.flashcards.isEmpty) {
      return Scaffold(
        backgroundColor: VoxColors.bg(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          iconTheme: IconThemeData(color: VoxColors.onBg(context)),
        ),
        body: Center(
          child: Text('No cards',
              style: TextStyle(color: VoxColors.textSecondary(context))),
        ),
      );
    }

    final card = widget.flashcards[_currentCard];
    final isFlipped = _flipped[_currentCard];
    final total = widget.flashcards.length;

    return Scaffold(
      backgroundColor: VoxColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: VoxColors.onBg(context), size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: VoxColors.onBg(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentCard + 1) / total,
                  backgroundColor: VoxColors.onBg(context).withValues(alpha: 0.05),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(VoxColors.primary(context)),
                  minHeight: 3,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _flipped[_currentCard] = !isFlipped),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: isFlipped
                          ? VoxColors.surface2(context)
                          : VoxColors.surface(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: VoxColors.border(context)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isFlipped ? 'ANSWER' : 'QUESTION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: VoxColors.primary(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          isFlipped ? card.answer : card.question,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.6,
                            fontWeight: FontWeight.w700,
                            color: VoxColors.onBg(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _currentCard > 0
                          ? () => setState(() {
                                _currentCard--;
                                _flipped[_currentCard] = false;
                              })
                          : null,
                      child: const Text('← Previous'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _currentCard < total - 1
                          ? () => setState(() {
                                _currentCard++;
                                _flipped[_currentCard] = false;
                              })
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VoxColors.primary(context),
                      ),
                      child: Text('Next →',
                          style: TextStyle(color: VoxColors.onPrimary(context))),
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
}
