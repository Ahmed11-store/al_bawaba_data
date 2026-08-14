/// Arabic License Plate Normalizer
/// ---------------------------------------------------------------
/// Pure, dependency-free normalization logic for turning raw
/// on-device speech-recognition output into a clean plate token
/// stream of [Letters] + [Digits], matching Saudi/Gulf-style plate
/// dictation patterns (e.g. "ر ص ل ٨ ٤ ٣ ٥" -> letters: "رصل",
/// digits: "8435").
///
/// This file has ZERO external package dependencies so it can be
/// unit-tested in isolation and reused by both the STT service and
/// any offline batch-import / CSV-seeding tooling.
library arabic_plate_normalizer;

/// The fixed set of Arabic letters legally used on Gulf-style
/// vehicle plates. Extend/trim this list to match the exact
/// jurisdiction the app is deployed in.
const Set<String> kValidPlateLetters = {
  'ا', 'ب', 'ح', 'د', 'ر', 'س', 'ص', 'ط', 'ع', 'ق', 'ك', 'ل', 'م', 'ن', 'ه',
  'و', 'ي', 'ج', 'ز', 'ش', 'غ', 'ف', 'ت', 'ث', 'خ', 'ذ', 'ض', 'ظ',
};

/// Words STT engines commonly hallucinate around numerals/letters
/// during rapid dictation ("رقم", "لوحة", "صفر" spoken as a filler,
/// silence markers, etc). These are stripped before parsing.
const Set<String> kNoiseTokens = {
  'رقم',
  'لوحة',
  'اللوحة',
  'بلاك',
  'بليت',
  'يعني',
  'اه',
  'أه',
  'امم',
  'حرف',
  'ارقام',
  'أرقام',
};

/// Maps common Arabic number-words to digits, since some offline
/// STT engines (especially generic dictation grammars not tuned
/// for plates) will emit "خمسة" instead of "٥" / "5".
const Map<String, String> kArabicNumberWords = {
  'صفر': '0',
  'واحد': '1',
  'اثنين': '2',
  'إثنين': '2',
  'اثنان': '2',
  'ثلاثة': '3',
  'ثلاث': '3',
  'اربعة': '4',
  'أربعة': '4',
  'اربع': '4',
  'خمسة': '5',
  'خمس': '5',
  'ستة': '6',
  'ست': '6',
  'سبعة': '7',
  'سبع': '7',
  'ثمانية': '8',
  'ثماني': '8',
  'تسعة': '9',
  'تسع': '9',
};

/// Result of normalizing one utterance / rolling buffer into a
/// structured plate candidate.
class PlateToken {
  final String letters; // normalized Arabic letters only, e.g. "رصل"
  final String digits; // normalized ASCII digits only, e.g. "8435"
  final String raw; // original unmodified input, for logging/debug

  const PlateToken({
    required this.letters,
    required this.digits,
    required this.raw,
  });

  /// A plate is only "complete" and eligible for DB lookup once it
  /// has at least one letter and a jurisdiction-appropriate digit
  /// count. Adjust [minDigits]/[maxDigits] to match local plate
  /// formats (Saudi plates: 3 letters + up to 4 digits).
  bool isComplete({int minLetters = 1, int minDigits = 1, int maxDigits = 4}) {
    return letters.length >= minLetters &&
        digits.length >= minDigits &&
        digits.length <= maxDigits;
  }

  /// Canonical display string, RTL-safe: letters block then digits
  /// block, space separated (matches the UI table columns
  /// [الحروف] / [الأرقام]).
  String get display => '$letters $digits'.trim();

  @override
  String toString() =>
      'PlateToken(letters: $letters, digits: $digits, raw: "$raw")';
}

class ArabicPlateNormalizer {
  const ArabicPlateNormalizer();

  /// Converts Eastern Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩) and
  /// Persian variants (۰۱۲۳۴۵۶۷۸۹) to standard ASCII digits.
  String convertDigitsToAscii(String input) {
    const easternArabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();

    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final eastIdx = easternArabic.indexOf(char);
      final persIdx = persian.indexOf(char);
      if (eastIdx != -1) {
        buffer.write(eastIdx.toString());
      } else if (persIdx != -1) {
        buffer.write(persIdx.toString());
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Strips Arabic diacritics (tashkeel), tatweel elongation, and
  /// normalizes letter variants (أ/إ/آ -> ا, ة -> ه, ى -> ي) so
  /// STT variance doesn't cause false plate mismatches.
  String normalizeLetterVariants(String input) {
    var s = input;

    // Strip tashkeel/diacritics (Unicode combining marks range).
    s = s.replaceAll(RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'), '');

    // Strip tatweel (elongation character).
    s = s.replaceAll('\u0640', '');

    // Normalize hamza variants to bare alif.
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا');

    // Normalize teh marbuta -> heh (common plate-letter confusion).
    s = s.replaceAll('ة', 'ه');

    // Normalize alef maksura -> yeh.
    s = s.replaceAll('ى', 'ي');

    return s;
  }

  /// Replaces recognized Arabic number-words with digits, and
  /// removes known noise/filler tokens, working on whitespace
  /// separated tokens so we don't corrupt letters mid-word.
  String stripNoiseAndSpokenNumbers(String input) {
    final tokens = input.trim().split(RegExp(r'\s+'));
    final out = <String>[];

    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;
      if (kNoiseTokens.contains(token)) continue;

      final asDigit = kArabicNumberWords[token];
      if (asDigit != null) {
        out.add(asDigit);
        continue;
      }
      out.add(token);
    }
    return out.join(' ');
  }

  /// Full pipeline: raw STT partial/final result -> [PlateToken].
  /// Applies the grammar-constraint filter described in the spec:
  /// only valid plate letters and digits survive; everything else
  /// (filler words, unrelated vocabulary) is discarded.
  PlateToken normalize(String rawRecognizedText) {
    final raw = rawRecognizedText;

    var text = convertDigitsToAscii(rawRecognizedText);
    text = normalizeLetterVariants(text);
    text = stripNoiseAndSpokenNumbers(text);

    final letterBuffer = StringBuffer();
    final digitBuffer = StringBuffer();

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (kValidPlateLetters.contains(char)) {
        letterBuffer.write(char);
      } else if (RegExp(r'[0-9]').hasMatch(char)) {
        digitBuffer.write(char);
      }
      // Anything else (spaces, stray punctuation, non-plate
      // vocabulary that slipped through) is silently dropped —
      // this IS the grammar constraint filter.
    }

    return PlateToken(
      letters: letterBuffer.toString(),
      digits: digitBuffer.toString(),
      raw: raw,
    );
  }
}
