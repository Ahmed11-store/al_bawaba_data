/// Blacklist Import + Scan-Log Export Service (100% offline)
/// ---------------------------------------------------------------
/// Two directions of local file I/O, both fully on-device:
///   - importBlacklistFromFile: seeds/updates the SQLite blacklist
///     table from a local CSV or JSON file the operator picks with
///     `file_picker` (no network fetch involved).
///   - exportLogsToCsv: writes the "الكل" master log (or the
///     "مطلوبة" filtered set) out to a local CSV file the operator
///     can share/save, backing the "تنزيل" button.
///
/// pubspec.yaml dependencies this file assumes:
///   csv: ^6.0.0
///   file_picker: ^8.1.2
///   path_provider: ^2.1.4
///   share_plus: ^10.0.2
library import_export_service;

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/plate_record.dart';
import '../models/scan_log.dart';

class ImportResult {
  final List<PlateRecord> records;
  final int skippedRows;
  const ImportResult({required this.records, required this.skippedRows});
}

class ImportExportService {
  /// Opens the native file picker restricted to csv/json, parses
  /// the chosen local file, and returns parsed [PlateRecord]s ready
  /// for [DatabaseService.replaceBlacklist] / `appendBlacklist`.
  /// Returns null if the operator cancels the picker.
  Future<ImportResult?> pickAndParseBlacklistFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;

    final content = utf8.decode(bytes, allowMalformed: true);
    final isJson = (file.extension ?? '').toLowerCase() == 'json';

    return isJson ? _parseJson(content) : _parseCsv(content);
  }

  /// Loads the small demo dataset bundled at
  /// assets/data/sample_blacklist.json (declared under `assets:`
  /// in pubspec.yaml). Intended for first-run seeding so the app
  /// has something to match against before an operator imports
  /// the real 50,000+ record file — call this from app startup
  /// only when [DatabaseService.blacklistCount] is zero.
  Future<ImportResult> loadBundledSampleBlacklist() async {
    final content =
        await rootBundle.loadString('assets/data/sample_blacklist.json');
    return _parseJson(content);
  }

  ImportResult _parseJson(String content) {
    final decoded = jsonDecode(content);
    final rows = decoded is List
        ? decoded
        : (decoded is Map && decoded['records'] is List
            ? decoded['records'] as List
            : const []);

    final records = <PlateRecord>[];
    var skipped = 0;

    for (final row in rows) {
      if (row is! Map) {
        skipped++;
        continue;
      }
      final record =
          PlateRecord.fromSeedRow(Map<String, dynamic>.from(row));
      if (record.letters.isEmpty || record.digits.isEmpty) {
        skipped++;
        continue;
      }
      records.add(record);
    }

    return ImportResult(records: records, skippedRows: skipped);
  }

  ImportResult _parseCsv(String content) {
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(content, fieldDelimiter: ',');

    if (rows.isEmpty) return const ImportResult(records: [], skippedRows: 0);

    final header =
        rows.first.map((h) => h.toString().trim()).toList(growable: false);
    final records = <PlateRecord>[];
    var skipped = 0;

    for (var i = 1; i < rows.length; i++) {
      final rowValues = rows[i];
      if (rowValues.length != header.length) {
        skipped++;
        continue;
      }
      final rowMap = <String, dynamic>{
        for (var c = 0; c < header.length; c++) header[c]: rowValues[c],
      };
      final record = PlateRecord.fromSeedRow(rowMap);
      if (record.letters.isEmpty || record.digits.isEmpty) {
        skipped++;
        continue;
      }
      records.add(record);
    }

    return ImportResult(records: records, skippedRows: skipped);
  }

  /// Writes [logs] to a local CSV file under the app's documents
  /// directory and opens the native share sheet ("تنزيل" action) so
  /// the operator can save it to Files / Drive / send it onward.
  /// The file itself is written entirely on-device.
  Future<File> exportLogsToCsv(
    List<ScanLog> logs, {
    String fileName = 'al_bawaba_logs',
  }) async {
    final rows = <List<dynamic>>[
      [
        'الحروف',
        'الأرقام',
        'الحالة',
        'التاريخ والوقت',
        'خط العرض',
        'خط الطول',
        'البنك',
        'نوع المركبة',
        'رقم الشاسيه',
      ],
      for (final log in logs)
        [
          log.letters,
          log.digits,
          log.status.arabicLabel,
          log.timestamp.toIso8601String(),
          log.latitude ?? '',
          log.longitude ?? '',
          log.matchedBankName ?? '',
          log.matchedVehicleModel ?? '',
          log.matchedChassisNumber ?? '',
        ],
    ];

    final csvContent = const ListToCsvConverter().convert(rows);
    // Prepend a UTF-8 BOM so Excel opens Arabic text correctly
    // instead of mangling it into mojibake.
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csvContent)];

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${fileName}_$timestamp.csv');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: 'سجلات البوابة');

    return file;
  }
}
