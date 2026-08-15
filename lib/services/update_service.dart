/// Update Checker (GitHub Releases as the "update server")
/// ---------------------------------------------------------------
/// Checks whether a newer version is published as a GitHub Release
/// on a repo you control, using GitHub's public API — no server of
/// your own needed. To ship an update: create a new Release on
/// GitHub with a tag like `v1.1.0` and attach the new APK as a
/// release asset. That's it; every installed copy of the app will
/// see it on its next launch.
///
/// Honest limit (this is an Android OS rule, not something this
/// code can work around): a normal sideloaded app can never
/// silently install its own update. The operator will always see
/// Android's own "install this app?" confirmation at least once.
/// What this DOES fully automate: checking for updates and getting
/// the operator to the right download with one tap, with zero
/// manual "did the customer check for an update" work on your side.
///
/// SETUP — fill in your own repo below:
///   kUpdateRepoOwner: your GitHub username or org
///   kUpdateRepoName: a repo you control (can be empty of source
///     code — it only needs Releases with APKs attached)
///
/// Release tag format expected: `v1.2.3` or `1.2.3` (the leading
/// "v" is optional and stripped automatically).
///
/// pubspec.yaml dependencies this file assumes:
///   package_info_plus: ^8.0.2
///
/// Add to AndroidManifest.xml (needed for the update check itself
/// and for opening the download link — the app is otherwise fully
/// offline, this is the one deliberate exception):
///   <uses-permission android:name="android.permission.INTERNET"/>
library update_service;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// TODO: replace with your own GitHub username/org and repo name.
const String kUpdateRepoOwner = 'your-github-username';
const String kUpdateRepoName = 'al-bawaba-releases';

class UpdateInfo {
  final String latestVersion;
  final String apkDownloadUrl;
  final String releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.apkDownloadUrl,
    required this.releaseNotes,
  });
}

class UpdateService {
  UpdateService._internal();
  static final UpdateService instance = UpdateService._internal();

  /// Returns update info if a newer version is available, or null
  /// if the app is current / the check fails for any reason (no
  /// internet, GitHub unreachable, no releases yet, etc.) — a
  /// failed check should never block or nag the operator, since the
  /// app must keep working fully offline regardless.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final currentVersion = (await PackageInfo.fromPlatform()).version;

      final uri = Uri.https(
        'api.github.com',
        '/repos/$kUpdateRepoOwner/$kUpdateRepoName/releases/latest',
      );
      final response = await http
          .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final latestVersion = _stripLeadingV(tagName);
      if (latestVersion.isEmpty) return null;

      if (!_isNewer(latestVersion, currentVersion)) return null;

      final assets = (data['assets'] as List?) ?? const [];
      String? apkUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (apkUrl == null) return null;

      return UpdateInfo(
        latestVersion: latestVersion,
        apkDownloadUrl: apkUrl,
        releaseNotes: (data['body'] as String?)?.trim() ?? '',
      );
    } catch (_) {
      // Network unavailable, GitHub unreachable, malformed response,
      // etc. — silently skip. This check is a nice-to-have, never a
      // requirement for the app to keep working.
      return null;
    }
  }

  String _stripLeadingV(String tag) {
    final t = tag.trim();
    return t.startsWith('v') || t.startsWith('V') ? t.substring(1) : t;
  }

  /// Simple dotted-numeric version compare (`1.2.10` > `1.2.9`).
  /// Falls back to false (not newer) on anything unparseable rather
  /// than risking a false "update available" loop.
  bool _isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    final a = parse(latest);
    final b = parse(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av > bv;
    }
    return false;
  }
}
