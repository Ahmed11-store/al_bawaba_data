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
  /// has the jurisdiction's letter count and an appropriate digit
  /// count. Default of 3 letters matches every example plate in
  /// this project (sample_blacklist.json, README). Adjust
  /// [minLetters]/[maxDigits] to match local plate formats.
  bool isComplete({int minLetters = 3, int minDigits = 1, int maxDigits = 4}) {
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
  /// ---------------------------------------------------------------
  /// Works at the WORD/TOKEN level, not the character level. This
  /// matters: [kValidPlateLetters] covers almost the entire Arabic
  /// alphabet, so a naive "keep every character that's a valid
  /// plate letter" scan over the raw utterance ends up absorbing
  /// the letters of ANY ordinary Arabic word the operator happens
  /// to say — not just the dictated plate — since nearly every
  /// Arabic word is, character-by-character, built only from
  /// [kValidPlateLetters]. That was the source of extra/garbage
  /// characters showing up in captured plates. Instead:
  ///   - a token that's a known noise word is dropped
  ///   - a token that's a spoken number word ("خمسة") becomes a digit
  ///   - a token that's purely numeric ("8" or "8435") is kept as-is
  ///   - a token that is exactly ONE Arabic letter (plates are meant
  ///     to be dictated letter-by-letter, per this app's spec) is
  ///     kept as a plate letter
  ///   - a SHORT token (2–[maxFusedLetters] characters) made ENTIRELY
  ///     of valid plate letters is also kept, as-is, as fused plate
  ///     letters — see below for why this exists
  ///   - anything else — real words, long multi-letter tokens, stray
  ///     punctuation — is discarded, since it's not plate dictation
  ///
  /// Why the fused-token case exists: on-device Arabic dictation
  /// engines routinely merge quickly-spoken individual letters into
  /// one word-like chunk — an operator saying "ر... ص... ل..." can
  /// easily come back from the engine as the single token "رصل"
  /// instead of three space-separated single characters. Without
  /// this case, every one of those letters was silently dropped
  /// (each fused token failed the "exactly one letter" check and
  /// fell into the discard bucket), which is what produced plates
  /// with missing/wrong letters even when the operator dictated
  /// correctly. This can't perfectly distinguish "three plate
  /// letters said quickly" from "a genuine short Arabic word that
  /// happens to be built only from plate-valid letters" — that
  /// ambiguity is inherent to letter-by-letter dictation without a
  /// plate-specific acoustic grammar (see the class doc comment
  /// above re: swapping in a custom Vosk model). The length cap
  /// keeps it from absorbing longer real words; kNoiseTokens keeps
  /// common filler phrases out either way.
  PlateToken normalize(String rawRecognizedText, {int maxFusedLetters = 6}) {
    final raw = rawRecognizedText;

    var text = convertDigitsToAscii(rawRecognizedText);
    text = normalizeLetterVariants(text);

    final letterBuffer = StringBuffer();
    final digitBuffer = StringBuffer();
    final numericTokenPattern = RegExp(r'^[0-9]+$');

    bool isAllValidPlateLetters(String token) {
      for (final rune in token.runes) {
        if (!kValidPlateLetters.contains(String.fromCharCode(rune))) {
          return false;
        }
      }
      return true;
    }

    for (final rawToken in text.trim().split(RegExp(r'\s+'))) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;
      if (kNoiseTokens.contains(token)) continue;

      final asDigit = kArabicNumberWords[token];
      if (asDigit != null) {
        digitBuffer.write(asDigit);
        continue;
      }

      if (numericTokenPattern.hasMatch(token)) {
        digitBuffer.write(token);
        continue;
      }

      final letterCount = token.runes.length;
      if (letterCount == 1 && kValidPlateLetters.contains(token)) {
        letterBuffer.write(token);
        continue;
      }

      if (letterCount >= 2 &&
          letterCount <= maxFusedLetters &&
          isAllValidPlateLetters(token)) {
        letterBuffer.write(token);
        continue;
      }

      // Long word, punctuation, or otherwise unrelated speech —
      // intentionally not part of the plate. Dropped.
    }

    return PlateToken(
      letters: letterBuffer.toString(),
      digits: digitBuffer.toString(),
      raw: raw,
    );
  }
}
