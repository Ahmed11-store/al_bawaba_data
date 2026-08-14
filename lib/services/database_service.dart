/// Local SQLite Database Service (100% offline)
/// ---------------------------------------------------------------
/// Owns the two tables the whole app is built around:
///   - blacklist   : the "wanted plates" reference table (seeded
///                   from CSV/JSON, supports 50,000+ rows).
///   - scan_logs   : every plate the STT engine recognized during
///                   any session, safe or wanted.
///
/// Both `letters` and `digits` are indexed together so a lookup on
/// a freshly-recognized plate is a single indexed equality query —
/// this is what keeps match latency under ~20ms even at 50k+ rows
/// on typical mid-range Android hardware.
///
/// pubspec.yaml dependency this file assumes:
///   sqflite: ^2.3.3
///   path: ^1.9.0
library database_service;

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/plate_record.dart';
import '../models/scan_log.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  static const String _dbName = 'al_bawaba.db';
  static const int _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        // Foreign keys off by design — scan_logs intentionally
        // denormalizes matched blacklist fields rather than FK-ing,
        // so historical logs stay intact even if a blacklist entry
        // is later removed/updated.
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE blacklist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            letters TEXT NOT NULL,
            digits TEXT NOT NULL,
            bank_name TEXT,
            vehicle_model TEXT,
            chassis_number TEXT
          )
        ''');
        // Composite index — the hot path is
        // "WHERE letters = ? AND digits = ?".
        await db.execute('''
          CREATE INDEX idx_blacklist_plate
          ON blacklist (letters, digits)
        ''');

        await db.execute('''
          CREATE TABLE scan_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            letters TEXT NOT NULL,
            digits TEXT NOT NULL,
            status TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            matched_bank_name TEXT,
            matched_vehicle_model TEXT,
            matched_chassis_number TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_scan_logs_timestamp
          ON scan_logs (timestamp)
        ''');
        await db.execute('''
          CREATE INDEX idx_scan_logs_status
          ON scan_logs (status)
        ''');
      },
    );
  }

  // ---------------------------------------------------------------
  // Blacklist matching engine
  // ---------------------------------------------------------------

  /// Indexed point lookup — the <20ms match query. Returns null on
  /// no match (silently logged as "سليمة" by the caller).
  Future<PlateRecord?> lookupPlate({
    required String letters,
    required String digits,
  }) async {
    final db = await database;
    final rows = await db.query(
      'blacklist',
      where: 'letters = ? AND digits = ?',
      whereArgs: [letters, digits],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PlateRecord.fromMap(rows.first);
  }

  Future<int> blacklistCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) AS c FROM blacklist');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Backs the "عرض اللوحات المستوردة" browse screen — the imported
  /// blacklist previously had no way to be viewed, only counted.
  /// [search], if given, filters on letters OR digits containing
  /// the (already best-effort normalized) query text. Capped by
  /// [limit] since the table can hold 50,000+ rows.
  Future<List<PlateRecord>> getBlacklist({String? search, int limit = 200}) async {
    final db = await database;
    List<Map<String, Object?>> rows;
    if (search == null || search.trim().isEmpty) {
      rows = await db.query(
        'blacklist',
        orderBy: 'id DESC',
        limit: limit,
      );
    } else {
      final q = '%${search.trim()}%';
      rows = await db.query(
        'blacklist',
        where: 'letters LIKE ? OR digits LIKE ?',
        whereArgs: [q, q],
        orderBy: 'id DESC',
        limit: limit,
      );
    }
    return rows.map(PlateRecord.fromMap).toList();
  }

  /// Wipes and reseeds the blacklist table. Used by the CSV/JSON
  /// import flow — always a clean, atomic replace so a partial or
  /// stale import can never leave the table in a mixed state.
  Future<void> replaceBlacklist(List<PlateRecord> records) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('blacklist');
      final batch = txn.batch();
      for (final r in records) {
        batch.insert('blacklist', r.toMap());
      }
      // noResult: true avoids allocating a result row per insert —
      // meaningful at 50k+ rows.
      await batch.commit(noResult: true);
    });
  }

  /// Appends records without clearing existing ones (incremental
  /// updates from a partial CSV).
  Future<void> appendBlacklist(List<PlateRecord> records) async {
    final db = await database;
    final batch = db.batch();
    for (final r in records) {
      batch.insert('blacklist', r.toMap());
    }
    await batch.commit(noResult: true);
  }

  // ---------------------------------------------------------------
  // Scan logs
  // ---------------------------------------------------------------

  Future<int> insertScanLog(ScanLog log) async {
    final db = await database;
    return db.insert('scan_logs', log.toMap());
  }

  /// All "مطلوبة" matches, most recent first — backs the "سجل
  /// المطابقات" screen.
  Future<List<ScanLog>> getWantedLogs() async {
    final db = await database;
    final rows = await db.query(
      'scan_logs',
      where: 'status = ?',
      whereArgs: ['wanted'],
      orderBy: 'timestamp DESC',
    );
    return rows.map(ScanLog.fromMap).toList();
  }

  /// Every scan (safe + wanted) from the last [hours] — backs the
  /// "الكل" master log tab. Defaults to 48 hours per spec.
  Future<List<ScanLog>> getRecentLogs({int hours = 48}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(hours: hours)).toIso8601String();
    final rows = await db.query(
      'scan_logs',
      where: 'timestamp >= ?',
      whereArgs: [cutoff],
      orderBy: 'timestamp DESC',
    );
    return rows.map(ScanLog.fromMap).toList();
  }

  /// Housekeeping: permanently deletes scan logs older than
  /// [olderThanHours]. Wire this to a periodic background call
  /// (e.g. on app start) if unattended storage growth is a
  /// concern — not called automatically, so historical data is
  /// never lost without an explicit decision by the integrator.
  Future<int> purgeLogsOlderThan({int olderThanHours = 48}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(hours: olderThanHours))
        .toIso8601String();
    return db.delete(
      'scan_logs',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
