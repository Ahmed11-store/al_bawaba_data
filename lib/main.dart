import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'providers/inspection_provider.dart';
import 'screens/app_gate.dart';
import 'services/database_service.dart';
import 'services/import_export_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedSampleBlacklistIfEmpty();
  runApp(const AlBawabaApp());
}

/// First-run convenience seed: if the blacklist table is empty
/// (fresh install, before the operator has imported the real
/// 50,000+ record file), load the small bundled demo dataset so
/// the matching engine has something to demonstrate against.
/// Safe to call every launch — it's a no-op once any data exists.
Future<void> _seedSampleBlacklistIfEmpty() async {
  final db = DatabaseService.instance;
  final count = await db.blacklistCount();
  if (count > 0) return;

  final result = await ImportExportService().loadBundledSampleBlacklist();
  if (result.records.isNotEmpty) {
    await db.replaceBlacklist(result.records);
  }
}

class AlBawabaApp extends StatelessWidget {
  const AlBawabaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => InspectionProvider(),
      child: MaterialApp(
        title: 'البوابة - Al-Bawaba',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        // RTL is applied explicitly by each screen via
        // Directionality(TextDirection.rtl) rather than forcing an
        // app-wide `locale` — that would need the
        // flutter_localizations package wired in to avoid a silent
        // fallback-locale warning, which this single-purpose,
        // Arabic-only operational tool doesn't otherwise need.
        home: const AppGate(),
      ),
    );
  }
}
