/// Blacklist Data Sync (auto, silent, no install prompt needed)
/// ---------------------------------------------------------------
/// Separate from [UpdateService] (which updates the *app itself*
/// and always needs a tap — that's an Android OS rule). This
/// service updates the *wanted-plates data* only, which is just an
/// HTTP GET + a local database write — no OS permission dialog
/// involved, so this genuinely can run fully automatically with
/// zero operator interaction, exactly as asked for.
///
/// Reuses the same GitHub repo as [UpdateService] (see
/// update_service.dart for the owner/repo you already set up) — one
/// more file in it, `blacklist_sync.json`, committed on the branch
/// below. Whenever you want to push a new plates list to every
/// customer automatically:
///   1. Edit `blacklist_sync.json` in the repo with the new records.
///   2. Bump `"version"` by at least 1 (this is what tells every
///      installed app "there's something new" — forgetting to bump
///      it means nobody gets the update).
///   3. Commit/push. Every customer's app picks it up automatically
///      next time it's opened with internet available — no action
///      needed from them or from you beyond that push.
///
/// Expected file shape (same field names the manual CSV/JSON
/// importer already accepts — see PlateRecord.fromSeedRow):
///   {
///     "version": 2,
///     "updated_at": "2026-08-20",
///     "records": [
///       {"الحروف": "رصل", "الأرقام": "8435", "البنك": "...", ...},
///       ...
///     ]
///   }
///
/// This REPLACES the entire local blacklist table with the synced
/// list each time a newer version is found (same atomic
/// wipe+reseed DatabaseService.replaceBlacklist already uses for
/// manual imports) — the remote file is treated as the full,
/// authoritative list, not a diff/patch.
///
/// pubspec.yaml dependencies this file assumes:
///   http: ^1.2.2
///   shared_preferences: ^2.3.2
library blacklist_sync_service;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plate_record.dart';
import 'database_service.dart';
import 'update_service.dart' show kUpdateRepoOwner, kUpdateRepoName;

/// Which branch `blacklist_sync.json` lives on and its path in the
/// repo. Change kBlacklistSyncPath if you'd rather nest it in a
/// folder (e.g. 'data/blacklist_sync.json').
const String kBlacklistSyncBranch = 'main';
const String kBlacklistSyncPath = 'blacklist_sync.json';

class BlacklistSyncResult {
  final bool updated;
  final int recordCount;
  final int? newVersion;

  const BlacklistSyncResult._(this.updated, this.recordCount, this.newVersion);

  factory BlacklistSyncResult.noChange() =>
      const BlacklistSyncResult._(false, 0, null);

  factory BlacklistSyncResult.updated_(int count, int version) =>
      BlacklistSyncResult._(true, count, version);
}

class BlacklistSyncService {
  BlacklistSyncService._internal();
  static final BlacklistSyncService instance = BlacklistSyncService._internal();

  static const _kLastSyncedVersionKey = 'blacklist_sync_last_version_v1';

  /// Checks the remote file and, if it carries a higher "version"
  /// than what's already synced on this device, replaces the local
  /// blacklist table with it. Always safe to call on every app
  /// launch — no internet / an unchanged version / a malformed
  /// response all just resolve to [BlacklistSyncResult.noChange]
  /// rather than throwing, so a flaky connection can never disrupt
  /// the app's offline-first operation.
  Future<BlacklistSyncResult> syncIfNeeded() async {
    try {
      final uri = Uri.https(
        'raw.githubusercontent.com',
        '/$kUpdateRepoOwner/$kUpdateRepoName/$kBlacklistSyncBranch/$kBlacklistSyncPath',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return BlacklistSyncResult.noChange();

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final remoteVersion = (data['version'] as num?)?.toInt();
      if (remoteVersion == null) return BlacklistSyncResult.noChange();

      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt(_kLastSyncedVersionKey) ?? 0;
      if (remoteVersion <= localVersion) return BlacklistSyncResult.noChange();

      final rawRecords = (data['records'] as List?) ?? const [];
      final records = rawRecords
          .whereType<Map<String, dynamic>>()
          .map(PlateRecord.fromSeedRow)
          .where((r) => r.letters.isNotEmpty && r.digits.isNotEmpty)
          .toList();

      if (records.isEmpty) return BlacklistSyncResult.noChange();

      await DatabaseService.instance.replaceBlacklist(records);
      await prefs.setInt(_kLastSyncedVersionKey, remoteVersion);

      return BlacklistSyncResult.updated_(records.length, remoteVersion);
    } catch (_) {
      return BlacklistSyncResult.noChange();
    }
  }
}
