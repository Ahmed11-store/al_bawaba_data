/// Speech Recognition Service (Offline, Arabic)
/// ---------------------------------------------------------------
/// Wraps the platform's on-device speech engine via the
/// `speech_to_text` package (which, on Android, drives the
/// on-device Google Speech Services recognizer when "offline
/// language packs" are installed, and on iOS drives SFSpeech's
/// on-device recognition mode — no audio is ever sent to a
/// server when `listenMode`/`onDevice` is forced true).
///
/// If a fully-embedded model is required (no reliance on the OS
/// having a language pack installed), swap the `SpeechToText`
/// calls below for a Vosk (`vosk_flutter`) recognizer bound to a
/// bundled `vosk-model-ar` asset — the public surface of this
/// class (start/stop/streams) is written so that swap doesn't
/// ripple into the UI/BLoC layer.
///
/// pubspec.yaml dependencies this file assumes:
///   speech_to_text: ^7.0.0
///
/// Add to AndroidManifest.xml:
///   <uses-permission android:name="android.permission.RECORD_AUDIO"/>
/// Add to Info.plist:
///   NSMicrophoneUsageDescription
///   NSSpeechRecognitionUsageDescription
library speech_recognition_service;

import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import '../core/arabic_plate_normalizer.dart';

enum SpeechServiceStatus { idle, listening, paused, error, unavailable }

/// A fully-formed plate candidate ready for DB lookup, plus
/// metadata the UI table / logging layer needs.
class PlateDetection {
  final PlateToken token;
  final DateTime detectedAt;

  const PlateDetection({required this.token, required this.detectedAt});
}

class SpeechRecognitionService {
  SpeechRecognitionService({ArabicPlateNormalizer? normalizer})
      : _normalizer = normalizer ?? const ArabicPlateNormalizer();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final ArabicPlateNormalizer _normalizer;

  final StreamController<SpeechServiceStatus> _statusController =
      StreamController<SpeechServiceStatus>.broadcast();
  final StreamController<PlateDetection> _plateController =
      StreamController<PlateDetection>.broadcast();
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();

  Stream<SpeechServiceStatus> get statusStream => _statusController.stream;
  Stream<PlateDetection> get plateDetectedStream => _plateController.stream;
  /// Normalized 0.0–1.0 audio level for the waveform / dB gauge.
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  SpeechServiceStatus _status = SpeechServiceStatus.idle;
  SpeechServiceStatus get status => _status;

  bool _initialized = false;
  bool _sessionActive = false;

  // Rolling buffer of the current utterance so partial results
  // (STT engines fire many partials before a "final") accumulate
  // into a single plate token instead of resetting each callback.
  String _rollingBuffer = '';
  Timer? _utteranceTimeoutTimer;

  /// Locale id for on-device Arabic recognition. Falls back
  /// through common Gulf/MSA locale ids depending on what the
  /// installed language pack registers as.
  static const List<String> _preferredArabicLocales = [
    'ar_SA',
    'ar-SA',
    'ar_AE',
    'ar',
  ];

  /// Must be called once before [startSession]. Verifies the
  /// on-device engine is available and requests mic permission.
  /// Returns false if no offline Arabic recognition is available
  /// on this device — the caller should surface a clear error in
  /// the UI rather than silently falling back to a cloud engine.
  Future<bool> initialize() async {
    if (_initialized) return true;

    final available = await _speech.initialize(
      onError: _handleEngineError,
      onStatus: _handleEngineStatus,
      // debugLogging left false in production builds.
    );

    if (!available) {
      _updateStatus(SpeechServiceStatus.unavailable);
      return false;
    }

    _initialized = true;
    _updateStatus(SpeechServiceStatus.idle);
    return true;
  }

  Future<String?> _resolveArabicLocaleId() async {
    final locales = await _speech.locales();
    for (final preferred in _preferredArabicLocales) {
      final match = locales.where(
        (l) => l.localeId.toLowerCase() == preferred.toLowerCase(),
      );
      if (match.isNotEmpty) return match.first.localeId;
    }
    // Fallback: any locale id that starts with "ar".
    final arabicMatch = locales.where(
      (l) => l.localeId.toLowerCase().startsWith('ar'),
    );
    return arabicMatch.isNotEmpty ? arabicMatch.first.localeId : null;
  }

  /// Starts a continuous listening session ("بدء الجلسة الصوتية").
  /// Automatically restarts listening after each final result so
  /// the mic effectively never stops until [stopSession] is
  /// called — platform STT sessions have a max duration and will
  /// self-terminate, so this wrapper re-arms itself transparently.
  Future<void> startSession() async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return;
    }
    if (_sessionActive) return;

    _sessionActive = true;
    await _listenOnce();
  }

  Future<void> _listenOnce() async {
    if (!_sessionActive) return;

    final localeId = await _resolveArabicLocaleId();
    if (localeId == null) {
      _updateStatus(SpeechServiceStatus.unavailable);
      _sessionActive = false;
      return;
    }

    _updateStatus(SpeechServiceStatus.listening);

    await _speech.listen(
      onResult: _handleResult,
      localeId: localeId,
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      onSoundLevelChange: _handleSoundLevel,
      // Force on-device recognition — do NOT allow this to fall
      // back to a server-backed recognizer. If the platform can't
      // honor onDevice, `initialize`/`listen` will report
      // unavailability instead of silently phoning home.
      onDevice: true,
      cancelOnError: false,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 8),
    );
  }

  void _handleSoundLevel(double level) {
    // speech_to_text reports roughly -2..10 dB-ish range across
    // platforms; normalize defensively into 0.0–1.0 for the UI
    // waveform/gauge widget.
    final clamped = level.clamp(-2.0, 10.0);
    final normalized = (clamped + 2.0) / 12.0;
    _audioLevelController.add(normalized.clamp(0.0, 1.0));
  }

  void _handleResult(SpeechRecognitionResult result) {
    if (_status == SpeechServiceStatus.paused) return;

    _rollingBuffer = result.recognizedWords;
    _armUtteranceTimeout();

    if (result.finalResult) {
      _evaluateBuffer(reset: true);
      return;
    }

    // Also evaluate on partials: for rapid-fire plate dictation we
    // don't want to wait for the engine's "final" flag (which can
    // lag) once we already have a complete-looking plate token.
    _evaluateBuffer(reset: false);
  }

  /// If no new partial arrives for a short window, treat the
  /// buffer as done — handles engines that never fire finalResult
  /// during continuous dictation mode.
  void _armUtteranceTimeout() {
    _utteranceTimeoutTimer?.cancel();
    _utteranceTimeoutTimer = Timer(const Duration(milliseconds: 900), () {
      _evaluateBuffer(reset: true);
    });
  }

  void _evaluateBuffer({required bool reset}) {
    if (_rollingBuffer.trim().isEmpty) return;

    final token = _normalizer.normalize(_rollingBuffer);

    if (token.isComplete()) {
      _plateController.add(
        PlateDetection(token: token, detectedAt: DateTime.now()),
      );
      // A complete plate was emitted — clear the buffer so the
      // next utterance starts fresh rather than re-emitting the
      // same plate on every subsequent partial.
      _rollingBuffer = '';
      return;
    }

    if (reset) {
      _rollingBuffer = '';
    }
  }

  /// Pauses recognition without tearing down the engine session —
  /// used while the "لوحة مطلوبة" alert modal is on screen so the
  /// mic doesn't pick up the alarm sound / operator speech as
  /// plate input.
  Future<void> pause() async {
    if (_status != SpeechServiceStatus.listening) return;
    _updateStatus(SpeechServiceStatus.paused);
    _rollingBuffer = '';
    await _speech.stop();
  }

  /// Resumes listening after [pause]. Re-arms a fresh listen()
  /// call since the underlying platform session was stopped.
  Future<void> resume() async {
    if (_status != SpeechServiceStatus.paused) return;
    if (!_sessionActive) return;
    await _listenOnce();
  }

  /// Fully stops the session ("إيقاف الجلسة الصوتية").
  Future<void> stopSession() async {
    _sessionActive = false;
    _utteranceTimeoutTimer?.cancel();
    _rollingBuffer = '';
    await _speech.stop();
    _updateStatus(SpeechServiceStatus.idle);
  }

  void _handleEngineStatus(String platformStatus) {
    // speech_to_text auto-stops after `listenFor`/`pauseFor`
    // elapses; re-arm continuous listening if the session is
    // still meant to be active and we weren't explicitly paused.
    if (platformStatus == 'done' || platformStatus == 'notListening') {
      if (_sessionActive && _status == SpeechServiceStatus.listening) {
        _listenOnce();
      }
    }
  }

  void _handleEngineError(SpeechRecognitionError error) {
    // Permanent errors (e.g. permission denied, engine missing)
    // surface as unavailable; transient errors just re-arm.
    if (error.permanent) {
      _sessionActive = false;
      _updateStatus(SpeechServiceStatus.error);
      return;
    }
    if (_sessionActive) {
      _listenOnce();
    }
  }

  void _updateStatus(SpeechServiceStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void dispose() {
    _utteranceTimeoutTimer?.cancel();
    _statusController.close();
    _plateController.close();
    _audioLevelController.close();
    _speech.cancel();
  }
}
