import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../language_provider.dart';
import '../theme_provider.dart';

/// Sync vs start-fresh choice for an email that already has a Vox account.
Future<bool?> showAccountDataSyncDialog(
  BuildContext context, {
  required String email,
}) {
  final lang = context.read<LanguageProvider>();
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      Widget choiceCard({
        required String title,
        required String body,
        required IconData icon,
        required bool keep,
      }) {
        return Material(
          color: VoxColors.cardFill(ctx),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => Navigator.pop(ctx, keep),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: keep
                      ? VoxColors.primary(ctx).withValues(alpha: 0.4)
                      : VoxColors.danger.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: keep ? VoxColors.primary(ctx) : VoxColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: VoxColors.onSurface(ctx),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: VoxColors.textSecondary(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        title: Text(lang.t('guest_save_sync_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                lang.tNamed('guest_save_sync_intro', {'email': email}),
                style: TextStyle(
                  height: 1.45,
                  color: VoxColors.textSecondary(ctx),
                ),
              ),
              const SizedBox(height: 16),
              choiceCard(
                title: lang.t('guest_save_sync_keep_title'),
                body: lang.t('guest_save_sync_keep_body'),
                icon: Icons.cloud_done_outlined,
                keep: true,
              ),
              const SizedBox(height: 10),
              choiceCard(
                title: lang.t('guest_save_sync_fresh_title'),
                body: lang.t('guest_save_sync_fresh_body'),
                icon: Icons.delete_forever_outlined,
                keep: false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lang.t('cancel')),
          ),
        ],
      );
    },
  );
}

/// Destructive confirmation before wiping existing cloud data.
Future<bool> showAccountFreshConfirmDialog(BuildContext context) async {
  final lang = context.read<LanguageProvider>();
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(lang.t('guest_save_fresh_confirm_title')),
      content: SingleChildScrollView(
        child: Text(
          lang.t('guest_save_fresh_confirm_body'),
          style: const TextStyle(height: 1.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(lang.t('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: VoxColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(lang.t('profile_email_fresh_confirm_button')),
        ),
      ],
    ),
  );
  return result ?? false;
}
