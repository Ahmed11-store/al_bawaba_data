/// Shared secret for offline activation-code signing (HMAC-SHA256).
/// ---------------------------------------------------------------
/// READ THIS BEFORE YOUR FIRST REAL RELEASE:
///
/// This value ships inside the compiled app so [LicenseService] can
/// verify an activation code with zero network access. That's the
/// whole point (you asked for 100% offline, even after payment) —
/// but it comes with one unavoidable tradeoff: anyone who
/// decompiles the APK can extract this string, and — since this
/// file is right here in the same project — the signing algorithm
/// too. With both, they could sign their own codes for their own
/// device code. There is no fully-offline scheme (no server at
/// all) that avoids this; it's not a bug, it's what "no backend"
/// costs. What this design DOES still stop, which matters more for
/// a small manually-invoiced subscription business:
///   - a customer can't guess or brute-force a working code
///   - a code you generate for one device can't be reused on
///     another device (see LicenseService — device id is bound in)
///   - a customer can't quietly extend their own subscription
///     without a code from you
/// If a customer is technical enough to decompile and re-sign APKs,
/// no purely offline scheme stops them — only a server-side check
/// would, which you said you don't want.
///
/// Two things to actually do:
///   1. Replace the string below with your own long random value
///      before shipping — this placeholder is not a secret, it's a
///      random-looking example.
///   2. Keep this exact value identical to the copy used by
///      `tool/generate_license.dart` — generated codes only verify
///      if both sides used the same secret. Never commit your real
///      production value to a public repo.
library license_secret;

const String kLicenseSecret =
    'CHANGE-ME-before-release-al-bawaba-x7Qm2pRt9L4vN-replace-this';

/// Fixed reference date used to encode an expiry date as a small
/// integer (days since this date) inside the activation code
/// payload. No need to ever change this once codes are in use.
final DateTime kLicenseEpoch = DateTime.utc(2025, 1, 1);
