/// Inspection Provider — the app's core orchestration state.
/// ---------------------------------------------------------------
/// Wires together, on every plate the offline STT engine detects:
///   1. optional GPS fix (if "الموقع" mode is on)
///   2. indexed SQLite blacklist lookup (<20ms)
///   3. scan_logs insert (silent if safe, alerted if wanted)
///   4. AudioAlertService trigger on a match
///
/// Screens subscribe to this via `provider`'s ChangeNotifier and
/// never talk to the STT/DB/GPS/audio services directly.
library inspection_provider;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/arabic_plate_normalizer.dart';
import '../models/plate_record.dart';
import '../models/scan_log.dart';
import '../services/audio_alert_service.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/speech_recognition_service.dart';

enum InspectionMode { fast, gps } // سريع / الموقع

class InspectionProvider extends ChangeNotifier {
  InspectionProvider({
    SpeechRecognitionService? speechService,
    AudioAlertService? audioAlertService,
    LocationService? locationService,
    DatabaseService? databaseService,
  })  : _speech = speechService ?? SpeechRecognitionService(),
        _location = locationService ?? LocationService(),
        _db = databaseService ?? DatabaseService.instance {
    _audioAlert = audioAlertService ?? AudioAlertService(speechService: _speech);
    _wirePlateDetection();
    _wireStatusStream();
    _wireAudioLevelStream();
  }

  final SpeechRecognitionService _speech;
  final LocationService _location;
  final DatabaseService _db;
  late final AudioAlertService _audioAlert;

  StreamSubscription<PlateDetection>? _plateSub;
  StreamSubscription<SpeechServiceStatus>? _statusSub;
  StreamSubscription<double>? _audioLevelSub;

  // ---- Public state the UI reads -------------------------------

  bool get isSessionActive =>
      _status == SpeechServiceStatus.listening ||
      _status == SpeechServiceStatus.paused;

  SpeechServiceStatus _status = SpeechServiceStatus.idle;
  SpeechServiceStatus get status => _status;

  InspectionMode _mode = InspectionMode.fast;
  InspectionMode get mode => _mode;

  double _audioLevel = 0.0;
  double get audioLevel => _audioLevel;

  /// Today's live session table — most recent scan first. Cleared
  /// only when the operator starts a brand-new session; persisted
  /// scans still live in scan_logs regardless.
  final List<ScanLog> sessionLog = [];

  /// The plate currently shown in the wanted-plate Alert Modal, if
  /// any. Null when no alert is active.
  ScanLog? activeAlertLog;
  PlateRecord? activeAlertRecord;

  Stream<bool> get alertActiveStream => _audioAlert.alertActiveStream;

  // ---- Lifecycle --------------------------------------------------

  Future<void> startSession() async {
    sessionLog.clear();
    notifyListeners();
    await _speech.startSession();
  }

  Future<void> stopSession() async {
    await _speech.stopSession();
  }

  void setMode(InspectionMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// Bound to the red "إغلاق" button on the Alert Modal.
  Future<void> dismissAlert() async {
    activeAlertLog = null;
    activeAlertRecord = null;
    await _audioAlert.dismiss();
    notifyListeners();
  }

  // ---- Wiring -------------------------------------------------------

  void _wireStatusStream() {
    _statusSub = _speech.statusStream.listen((s) {
      _status = s;
      notifyListeners();
    });
  }

  void _wireAudioLevelStream() {
    _audioLevelSub = _speech.audioLevelStream.listen((level) {
      _audioLevel = level;
      notifyListeners();
    });
  }

  void _wirePlateDetection() {
    _plateSub = _speech.plateDetectedStream.listen((detection) {
      unawaited(_handlePlateDetected(detection));
    });
  }

  Future<void> _handlePlateDetected(PlateDetection detection) async {
    final PlateToken token = detection.token;

    double? lat;
    double? lng;
    if (_mode == InspectionMode.gps) {
      final coords = await _location.getCurrentLocation();
      lat = coords?.latitude;
      lng = coords?.longitude;
    }

    final match = await _db.lookupPlate(
      letters: token.letters,
      digits: token.digits,
    );

    final log = ScanLog(
      letters: token.letters,
      digits: token.digits,
      status: match != null ? ScanStatus.wanted : ScanStatus.safe,
      timestamp: detection.detectedAt,
      latitude: lat,
      longitude: lng,
      matchedBankName: match?.bankName,
      matchedVehicleModel: match?.vehicleModel,
      matchedChassisNumber: match?.chassisNumber,
    );

    final insertedId = await _db.insertScanLog(log);
    final persisted = log.copyWith(id: insertedId);

    sessionLog.insert(0, persisted);
    notifyListeners();

    if (match != null) {
      activeAlertLog = persisted;
      activeAlertRecord = match;
      notifyListeners();
      await _audioAlert.triggerWantedPlateAlert();
    }
    // Safe matches are recorded silently — no alert, no UI
    // interruption — matching the spec's non-match behavior.
  }

  @override
  void dispose() {
    _plateSub?.cancel();
    _statusSub?.cancel();
    _audioLevelSub?.cancel();
    _speech.dispose();
    _audioAlert.dispose();
    super.dispose();
  }
}
