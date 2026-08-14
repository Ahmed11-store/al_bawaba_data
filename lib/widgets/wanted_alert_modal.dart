import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../providers/inspection_provider.dart';

/// "تم رصد لوحة مطلوبة" — shown as a non-dismissible-by-tap-outside
/// modal the instant a blacklist match is found. Only the red
/// "إغلاق" button can close it, which resumes the STT listener via
/// [InspectionProvider.dismissAlert].
class WantedAlertModal extends StatelessWidget {
  const WantedAlertModal({super.key});

  /// Call from the screen that hosts the live inspection view,
  /// e.g. inside a listener on `alertActiveStream`:
  ///
  /// ```dart
  /// showDialog(
  ///   context: context,
  ///   barrierDismissible: false,
  ///   builder: (_) => const WantedAlertModal(),
  /// );
  /// ```
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WantedAlertModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InspectionProvider>();
    final log = provider.activeAlertLog;
    final record = provider.activeAlertRecord;

    // Defensive: if the alert got cleared elsewhere while this
    // dialog was mid-transition, pop it instead of rendering blank.
    if (log == null || record == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: false, // block back-button / outside-tap dismissal
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_rounded,
                    color: AppColors.danger, size: 56),
                const SizedBox(height: 10),
                const Text(
                  'تم رصد لوحة مطلوبة',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    log.displayPlate,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _InfoRow(label: 'البنك', value: record.bankName),
                _InfoRow(label: 'نوع المركبة', value: record.vehicleModel),
                _InfoRow(label: 'رقم الشاسيه', value: record.chassisNumber),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: () async {
                      await context.read<InspectionProvider>().dismissAlert();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary)),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}
