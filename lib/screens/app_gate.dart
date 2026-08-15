import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/blacklist_sync_service.dart';
import '../services/license_service.dart';
import '../widgets/update_dialog.dart';
import 'activation_screen.dart';
import 'main_navigation.dart';

/// App entry point below [AlBawabaApp]: decides between the
/// activation screen and the real app based on [LicenseService]'s
/// fully-offline check. No network call happens anywhere in this
/// gate itself — the one-time update check (see
/// [_MainWithUpdateCheck]) only ever runs after activation already
/// succeeded, and silently no-ops with no internet available.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  late Future<LicenseStatus> _future;

  @override
  void initState() {
    super.initState();
    _future = LicenseService.instance.checkStatus();
  }

  void _recheck() {
    setState(() {
      _future = LicenseService.instance.checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LicenseStatus>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final status = snapshot.hasError
            ? const LicenseStatus(
                isActive: false,
                reason: 'حدث خطأ غير متوقع، أعد فتح التطبيق',
              )
            : snapshot.data!;
        if (status.isActive) {
          return const _MainWithUpdateCheck();
        }
        return ActivationScreen(status: status, onActivated: _recheck);
      },
    );
  }
}

/// Wraps [MainNavigation] and fires a single, silent, non-blocking
/// update check on first build. A failed/negative check never shows
/// anything — only an actual newer release pops the dialog.
class _MainWithUpdateCheck extends StatefulWidget {
  const _MainWithUpdateCheck();

  @override
  State<_MainWithUpdateCheck> createState() => _MainWithUpdateCheckState();
}

class _MainWithUpdateCheckState extends State<_MainWithUpdateCheck> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showUpdateDialogIfAvailable(context);
      _syncBlacklistSilently();
    });
  }

  /// Data-only sync — never needs a tap, unlike the app-update
  /// dialog (see update_dialog.dart for why those differ). Shows a
  /// brief SnackBar only when it actually replaced the local list,
  /// so the operator has visibility without anything blocking them.
  Future<void> _syncBlacklistSilently() async {
    final result = await BlacklistSyncService.instance.syncIfNeeded();
    if (!mounted || !result.updated) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تحديث قاعدة اللوحات المطلوبة تلقائيًا (${result.recordCount} لوحة).',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const MainNavigation();
}
