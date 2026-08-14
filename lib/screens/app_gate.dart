import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/license_service.dart';
import 'activation_screen.dart';
import 'main_navigation.dart';

/// App entry point below [AlBawabaApp]: decides between the
/// activation screen and the real app based on [LicenseService]'s
/// fully-offline check. No network call happens anywhere in this
/// path.
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

        final status = snapshot.data!;
        if (status.isActive) {
          return const MainNavigation();
        }
        return ActivationScreen(status: status, onActivated: _recheck);
      },
    );
  }
}
