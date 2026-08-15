import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../services/update_service.dart';

/// Shows a dismissible "update available" dialog. Never blocks
/// access to the app — an operator can always tap "لاحقًا" and keep
/// using the current version, since the offline core of the app
/// must never depend on this succeeding.
Future<void> showUpdateDialogIfAvailable(BuildContext context) async {
  final update = await UpdateService.instance.checkForUpdate();
  if (update == null) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('فيه تحديث جديد',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الإصدار ${update.latestVersion} متاح.',
                style: const TextStyle(color: AppColors.textSecondary)),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                update.releaseNotes,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'هيفتح المتصفح للتحميل، وبعدها هتشوف تأكيد التثبيت من أندرويد نفسه.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('لاحقًا'),
          ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(update.apkDownloadUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('تحميل التحديث'),
          ),
        ],
      ),
    ),
  );
}
