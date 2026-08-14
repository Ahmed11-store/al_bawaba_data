import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../models/scan_log.dart';

/// Scrollable table used by "الفحص" (live session) and "الكل"
/// (48h master log): [#] [الحروف] [الأرقام] [الحالة] [GPS icon].
class PlateDataTable extends StatelessWidget {
  const PlateDataTable({super.key, required this.logs});

  final List<ScanLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'لا توجد بيانات بعد',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: logs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final log = logs[index];
        final rowNumber = logs.length - index;
        final isWanted = log.status == ScanStatus.wanted;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isWanted ? AppColors.danger : AppColors.cardBorder,
              width: isWanted ? 1.2 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text('#$rowNumber',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  log.letters,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  log.digits,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: (isWanted ? AppColors.danger : AppColors.success)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    log.status.arabicLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isWanted ? AppColors.danger : AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: log.hasLocation
                    ? IconButton(
                        icon: const Icon(Icons.location_on,
                            color: AppColors.accentBlue, size: 20),
                        onPressed: () => _openInMaps(log),
                      )
                    : const Icon(Icons.location_off,
                        color: AppColors.textSecondary, size: 18),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openInMaps(ScanLog log) async {
    final uri = Uri.parse(log.googleMapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
