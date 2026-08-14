/// Minimal Crockford-style Base32 codec, zero dependencies.
/// ---------------------------------------------------------------
/// Used to turn a short signed license payload into a code an
/// operator can type by hand. The alphabet excludes I, L, O, U so a
/// misread/mistyped character is caught immediately rather than
/// silently decoding to a different, wrong value.
///
/// Shared verbatim by `lib/services/license_service.dart` (decode,
/// on-device) and `tool/generate_license.dart` (encode, run by the
/// developer on their own machine) — keep both in sync if you ever
/// change this file.
library base32_codec;

const String kBase32Alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String base32Encode(List<int> bytes) {
  final buffer = StringBuffer();
  var bitBuffer = 0;
  var bitCount = 0;
  for (final byte in bytes) {
    bitBuffer = (bitBuffer << 8) | (byte & 0xFF);
    bitCount += 8;
    while (bitCount >= 5) {
      bitCount -= 5;
      buffer.write(kBase32Alphabet[(bitBuffer >> bitCount) & 0x1F]);
    }
  }
  if (bitCount > 0) {
    buffer.write(kBase32Alphabet[(bitBuffer << (5 - bitCount)) & 0x1F]);
  }
  return buffer.toString();
}

/// Returns null if [input] contains a character outside the
/// Crockford alphabet once separators/whitespace are stripped.
List<int>? base32Decode(String input) {
  final bytes = <int>[];
  var bitBuffer = 0;
  var bitCount = 0;
  for (final rune in input.toUpperCase().runes) {
    final char = String.fromCharCode(rune);
    if (char == '-' || char.trim().isEmpty) continue;
    final index = kBase32Alphabet.indexOf(char);
    if (index == -1) return null;
    bitBuffer = (bitBuffer << 5) | index;
    bitCount += 5;
    if (bitCount >= 8) {
      bitCount -= 8;
      bytes.add((bitBuffer >> bitCount) & 0xFF);
    }
  }
  return bytes;
}
