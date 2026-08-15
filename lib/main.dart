import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'providers/inspection_provider.dart';
import 'screens/app_gate.dart';
import 'services/database_service.dart';
import 'services/import_export_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Deliberately not awaited-and-allowed-to-throw: see
  // _seedSampleBlacklistIfEmpty's own try/catch below for why this
  // must never be able to block runApp() from executing.
  await _seedSampleBlacklistIfEmpty();
  runApp(const AlBawabaApp());
}

/// First-run convenience seed: if the blacklist table is empty
/// (fresh install, before the operator has imported the real
/// 50,000+ record file), load the small bundled demo dataset so
/// the matching engine has something to demonstrate against.
/// Safe to call every launch — it's a no-op once any data exists.
///
/// Wrapped in try/catch on purpose: this runs inside main(), before
/// runApp() — an uncaught exception here (missing bundled asset, a
/// native plugin not yet registered after adding a new dependency,
/// a malformed sample file, anything) would stop the app before
/// Flutter ever attaches a single frame. That's indistinguishable
/// from a white screen that never goes away, and — unlike an error
/// that happens after runApp() — there's no widget tree yet for an
/// error screen to render into. Losing the demo seed data on a
/// fresh install is a minor inconvenience the operator can recover
/// from by importing their real file; failing to launch at all is
/// not recoverable from inside the app.
Future<void> _seedSampleBlacklistIfEmpty() async {
  try {
    final db = DatabaseService.instance;
    final count = await db.blacklistCount();
    if (count > 0) return;

    final result = await ImportExportService().loadBundledSampleBlacklist();
    if (result.records.isNotEmpty) {
      await db.replaceBlacklist(result.records);
    }
  } catch (_) {
    // Intentionally swallowed — see doc comment above.
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
