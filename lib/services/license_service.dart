/// Offline Monthly-Activation Service
/// ---------------------------------------------------------------
/// Fully offline license gate: no network call, ever. Payment
/// happens outside the app entirely (Vodafone Cash / InstaPay /
/// bank transfer to the developer); the developer then generates a
/// short activation code with `tool/generate_license.dart` and
/// sends it back to the operator, who types it in once here.
///
/// The code is:
///   - bound to this specific device (can't be copy-pasted onto a
///     different phone)
///   - signed with HMAC-SHA256 so it can't be forged without the
///     shared secret in `lib/core/license_secret.dart`
///   - self-describing an expiry date, checked against the device
///     clock with anti-rollback protection (see [_bumpLastSeen])
///
/// See license_secret.dart for the honest limits of what a fully
/// offline (no-server) scheme can and can't protect against.
///
/// pubspec.yaml dependencies this file assumes:
///   crypto: ^3.0.5
///   shared_preferences: ^2.3.2
library license_service;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/base32_codec.dart';
import '../core/license_secret.dart';

class LicenseStatus {
  final bool isActive;
  final DateTime? expiryDate; // null only when never activated
  final String reason;

  const LicenseStatus({
    required this.isActive,
    this.expiryDate,
    this.reason = '',
  });
}

class LicenseService {
  LicenseService._internal();
  static final LicenseService instance = LicenseService._internal();

  static const _kDeviceCodeKey = 'license_device_code_v1';
  static const _kActivationCodeKey = 'license_activation_code_v1';
  static const _kLastSeenEpochMsKey = 'license_last_seen_epoch_ms_v1';

  SharedPreferences? _prefsCache;

  Future<SharedPreferences> get _prefs async =>
      _prefsCache ??= await SharedPreferences.getInstance();

  /// 8-char hex device code, generated once and persisted forever.
  /// This is what the operator reads off the activation screen and
  /// sends to the developer — it's what a generated code gets
  /// bound to.
  Future<String> getOrCreateDeviceCode() async {
    final prefs = await _prefs;
    final existing = prefs.getString(_kDeviceCodeKey);
    if (existing != null && existing.length == 8) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(4, (_) => random.nextInt(256));
    final code = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    await prefs.setString(_kDeviceCodeKey, code);
    return code;
  }

  /// Attempts to activate with a code the operator typed in.
  /// Returns false if the code doesn't verify (wrong signature,
  /// wrong device, or malformed input) — the caller should show a
  /// clear error rather than guessing why.
  Future<bool> activate(String rawCode) async {
    final deviceCode = await getOrCreateDeviceCode();
    final expiry = _verifyAndDecode(rawCode, deviceCode);
    if (expiry == null) return false;

    final prefs = await _prefs;
    await prefs.setString(_kActivationCodeKey, _cleanCode(rawCode));
    await _bumpLastSeen();
    return true;
  }

  /// The single source of truth the app should check at launch
  /// (and after every successful [activate]) to decide whether to
  /// show the main app or the activation screen.
  ///
  /// Wrapped defensively: this runs during app startup, before
  /// anything else has rendered. If it throws — most commonly
  /// because a native plugin (shared_preferences) hasn't been
  /// re-registered after adding it without a full `flutter clean` —
  /// the exception would otherwise propagate out of AppGate's
  /// initState with no UI on screen yet to show an error, which is
  /// exactly what an unhandled white screen looks like. Falling
  /// back to "not activated" here means the operator sees the
  /// activation screen (recoverable) instead of a blank app.
  Future<LicenseStatus> checkStatus() async {
    try {
      final prefs = await _prefs;
      final deviceCode = await getOrCreateDeviceCode();
      final stored = prefs.getString(_kActivationCodeKey);

      final lastSeen = await _bumpLastSeen();

      if (stored == null) {
        return const LicenseStatus(
          isActive: false,
          reason: 'لم يتم تفعيل الاشتراك بعد',
        );
      }

      final expiry = _verifyAndDecode(stored, deviceCode);
      if (expiry == null) {
        // Shouldn't normally happen (we only ever store codes that
        // verified at activation time) — but if the secret/algorithm
        // ever changes, treat an unverifiable stored code as unset
        // rather than crashing.
        return const LicenseStatus(
          isActive: false,
          reason: 'كود التفعيل المحفوظ غير صالح، برجاء التفعيل من جديد',
        );
      }

      if (lastSeen.isAfter(expiry)) {
        return LicenseStatus(
          isActive: false,
          expiryDate: expiry,
          reason: 'انتهت صلاحية الاشتراك',
        );
      }

      return LicenseStatus(isActive: true, expiryDate: expiry);
    } catch (_) {
      return const LicenseStatus(
        isActive: false,
        reason: 'تعذر التحقق من التفعيل — أعد فتح التطبيق، ولو استمرت المشكلة أعد التفعيل',
      );
    }
  }

  /// Anti-rollback clock guard: persists the latest device time
  /// we've ever observed and never lets the "current time" used for
  /// expiry comparisons move backward, even if the operator turns
  /// the phone's clock back to try to keep an expired code "valid".
  /// Returns the effective (monotonic) "now" to compare against an
  /// expiry date.
  Future<DateTime> _bumpLastSeen() async {
    final prefs = await _prefs;
    final now = DateTime.now().millisecondsSinceEpoch;
    final storedLast = prefs.getInt(_kLastSeenEpochMsKey) ?? 0;
    final effective = now > storedLast ? now : storedLast;
    if (effective != storedLast) {
      await prefs.setInt(_kLastSeenEpochMsKey, effective);
    }
    return DateTime.fromMillisecondsSinceEpoch(effective, isUtc: false);
  }

  String _cleanCode(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();

  /// Verifies signature + device binding and, if valid, returns the
  /// encoded expiry date. Returns null on any failure — deliberately
  /// generic (doesn't distinguish "bad signature" from "wrong
  /// device" from "malformed") so a customer fumbling with a typo
  /// can't fish for hints about the code format.
  DateTime? _verifyAndDecode(String rawCode, String expectedDeviceCode) {
    final bytes = base32Decode(_cleanCode(rawCode));
    if (bytes == null || bytes.length != 10) return null;

    final payload = bytes.sublist(0, 6); // deviceId(4) + expiryDay(2)
    final signature = bytes.sublist(6, 10);
    final expectedSignature = _sign(payload);
    if (!_constantTimeEquals(signature, expectedSignature)) return null;

    final deviceIdHex = payload
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    if (deviceIdHex != expectedDeviceCode) return null;

    final expiryDay = (payload[4] << 8) | payload[5];
    return kLicenseEpoch.add(Duration(days: expiryDay)).toLocal();
  }

  List<int> _sign(List<int> payload) {
    final hmac = Hmac(sha256, utf8.encode(kLicenseSecret));
    return hmac.convert(payload).bytes.sublist(0, 4);
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
