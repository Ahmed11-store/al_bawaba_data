/// Blacklist plate record — one row of the local, offline
/// "wanted plates" reference table (loaded from CSV/JSON seed).
library plate_record;

import '../core/arabic_plate_normalizer.dart';

class PlateRecord {
  final int? id;
  final String letters; // normalized Arabic letters, e.g. "رصل"
  final String digits; // normalized digits, e.g. "8435"
  final String bankName; // البنك
  final String vehicleModel; // نوع المركبة
  final String chassisNumber; // رقم الشاسيه

  const PlateRecord({
    this.id,
    required this.letters,
    required this.digits,
    required this.bankName,
    required this.vehicleModel,
    required this.chassisNumber,
  });

  String get displayPlate => '$letters $digits';

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'letters': letters,
      'digits': digits,
      'bank_name': bankName,
      'vehicle_model': vehicleModel,
      'chassis_number': chassisNumber,
    };
  }

  factory PlateRecord.fromMap(Map<String, Object?> map) {
    return PlateRecord(
      id: map['id'] as int?,
      letters: (map['letters'] as String?) ?? '',
      digits: (map['digits'] as String?) ?? '',
      bankName: (map['bank_name'] as String?) ?? '',
      vehicleModel: (map['vehicle_model'] as String?) ?? '',
      chassisNumber: (map['chassis_number'] as String?) ?? '',
    );
  }

  /// Builds a record from a raw seed row (CSV/JSON), tolerant of
  /// either English or Arabic column headers so the same importer
  /// can read files exported from different back-office systems.
  ///
  /// CRITICAL: `letters`/`digits` are run through the exact same
  /// [ArabicPlateNormalizer] the live STT pipeline uses on every
  /// detected plate (see `SpeechRecognitionService._evaluateBuffer`).
  /// [DatabaseService.lookupPlate] is a plain `letters = ? AND
  /// digits = ?` equality query, so if a source file uses
  /// Arabic-Indic digits (٠-٩), hamza variants (أ/إ/آ), a ة instead
  /// of ه, etc., an un-normalized import would sit in the table
  /// forever and never match a real detection — it would still
  /// count toward blacklistCount() (looking "successfully
  /// imported"), just never actually alert. Do not remove this
  /// normalization step.
  factory PlateRecord.fromSeedRow(Map<String, dynamic> row) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = row[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return '';
    }

    const normalizer = ArabicPlateNormalizer();
    String normalizeLetters(String raw) {
      var s = normalizer.convertDigitsToAscii(raw);
      s = normalizer.normalizeLetterVariants(s);
      final buffer = StringBuffer();
      for (final rune in s.runes) {
        final char = String.fromCharCode(rune);
        if (kValidPlateLetters.contains(char)) buffer.write(char);
      }
      return buffer.toString();
    }

    String normalizeDigits(String raw) {
      final s = normalizer.convertDigitsToAscii(raw);
      final buffer = StringBuffer();
      for (final rune in s.runes) {
        final char = String.fromCharCode(rune);
        if (RegExp(r'[0-9]').hasMatch(char)) buffer.write(char);
      }
      return buffer.toString();
    }

    return PlateRecord(
      letters: normalizeLetters(pick(['letters', 'الحروف', 'plate_letters'])),
      digits: normalizeDigits(pick(['digits', 'الأرقام', 'plate_digits'])),
      bankName: pick(['bank_name', 'البنك', 'bank']),
      vehicleModel: pick(['vehicle_model', 'نوع المركبة', 'model']),
      chassisNumber: pick(['chassis_number', 'رقم الشاسيه', 'chassis']),
    );
  }
}
