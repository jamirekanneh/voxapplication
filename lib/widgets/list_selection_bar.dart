import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../language_provider.dart';
import '../theme_provider.dart';

/// Shared select-all checkbox + delete actions for list selection mode.
class ListSelectionBar extends StatelessWidget {
  const ListSelectionBar({
    super.key,
    required this.selectedCount,
    required this.visibleCount,
    required this.onCancel,
    required this.onToggleSelectAll,
    required this.onDelete,
    this.deleteLabel,
    this.foregroundOnPrimary = false,
  });

  final int selectedCount;
  final int visibleCount;
  final VoidCallback onCancel;
  final VoidCallback onToggleSelectAll;
  final VoidCallback? onDelete;
  final String? deleteLabel;
  final bool foregroundOnPrimary;

  bool? get _checkboxValue {
    if (visibleCount == 0) return false;
    if (selectedCount == visibleCount) return true;
    if (selectedCount > 0) return null;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final fg = foregroundOnPrimary
        ? VoxColors.onPrimary(context)
        : VoxColors.onBg(context);
    final accent = foregroundOnPrimary
        ? VoxColors.onPrimary(context)
        : VoxColors.primary(context);
    final checkboxFill = foregroundOnPrimary
        ? VoxColors.onPrimary(context)
        : VoxColors.primary(context);

    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.close, color: fg, size: 22),
          onPressed: onCancel,
          tooltip: lang.t('cancel'),
        ),
        Flexible(
          child: Text(
            lang.tNamed('selected_count', {'count': '$selectedCount'}),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: visibleCount > 0 ? onToggleSelectAll : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    tristate: true,
                    value: _checkboxValue,
                    onChanged: visibleCount > 0
                        ? (_) => onToggleSelectAll()
                        : null,
                    activeColor: checkboxFill,
                    checkColor: foregroundOnPrimary
                        ? VoxColors.primary(context)
                        : Colors.white,
                    side: BorderSide(color: accent.withValues(alpha: 0.7)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  lang.t('select_all'),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          onPressed: selectedCount > 0 ? onDelete : null,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(
            deleteLabel ?? lang.t('delete'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: VoxColors.danger,
            foregroundColor: Colors.white,
            disabledBackgroundColor: VoxColors.border(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }
}
