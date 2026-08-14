/// A single scan event row — every plate the offline STT engine
/// recognized, whether it matched the blacklist or not. Backs all
/// three tabs: الفحص (live table), مطلوبة (filtered wanted), الكل
/// (48h master log).
library scan_log;

enum ScanStatus { safe, wanted }

extension ScanStatusX on ScanStatus {
  String get dbValue => this == ScanStatus.wanted ? 'wanted' : 'safe';

  /// Arabic label used directly in the UI table's [الحالة] column.
  String get arabicLabel => this == ScanStatus.wanted ? 'مطلوبة' : 'سليمة';

  static ScanStatus fromDbValue(String value) =>
      value == 'wanted' ? ScanStatus.wanted : ScanStatus.safe;
}

class ScanLog {
  final int? id;
  final String letters;
  final String digits;
  final ScanStatus status;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  // Denormalized blacklist snapshot — populated only when
  // status == wanted, so the "مطلوبة" tab can render full match
  // detail without a join.
  final String? matchedBankName;
  final String? matchedVehicleModel;
  final String? matchedChassisNumber;

  const ScanLog({
    this.id,
    required this.letters,
    required this.digits,
    required this.status,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.matchedBankName,
    this.matchedVehicleModel,
    this.matchedChassisNumber,
  });

  String get displayPlate => '$letters $digits';
  bool get hasLocation => latitude != null && longitude != null;

  String get googleMapsUrl => hasLocation
      ? 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude'
      : '';

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'letters': letters,
      'digits': digits,
      'status': status.dbValue,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'matched_bank_name': matchedBankName,
      'matched_vehicle_model': matchedVehicleModel,
      'matched_chassis_number': matchedChassisNumber,
    };
  }

  factory ScanLog.fromMap(Map<String, Object?> map) {
    return ScanLog(
      id: map['id'] as int?,
      letters: (map['letters'] as String?) ?? '',
      digits: (map['digits'] as String?) ?? '',
      status: ScanStatusX.fromDbValue((map['status'] as String?) ?? 'safe'),
      timestamp: DateTime.tryParse((map['timestamp'] as String?) ?? '') ??
          DateTime.now(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      matchedBankName: map['matched_bank_name'] as String?,
      matchedVehicleModel: map['matched_vehicle_model'] as String?,
      matchedChassisNumber: map['matched_chassis_number'] as String?,
    );
  }

  ScanLog copyWith({int? id}) {
    return ScanLog(
      id: id ?? this.id,
      letters: letters,
      digits: digits,
      status: status,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      matchedBankName: matchedBankName,
      matchedVehicleModel: matchedVehicleModel,
      matchedChassisNumber: matchedChassisNumber,
    );
  }
}
