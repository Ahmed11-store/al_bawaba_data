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

  // Accumulates the plate currently being dictated, merged across
  // BOTH partial-result callbacks AND engine restarts (see
  // _ingest below for why restarts matter here). Cleared only on
  // commit, on a genuine settle-timeout, or on pause/stop.
  String _candidateLetters = '';
  String _candidateDigits = '';
  Timer? _settleTimer;

  /// How long to wait with no new speech before treating the
  /// accumulated candidate as finished and committing it. This is
  /// intentionally the ONLY thing that triggers a commit — see
  /// _ingest for why relying on the engine's own finalResult flag
  /// caused fragmented readings.
  static const Duration _settleDuration = Duration(milliseconds: 1600);

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
      // Long ceilings so the OS restarts the underlying recognizer
      // as rarely as possible; the platform still enforces its own
      // internal caps (varies by OEM/Android version) regardless of
      // what we request here, so _handleEngineStatus below is what
      // actually keeps the mic open past that — this just minimizes
      // how often that restart has to fire.
      listenFor: const Duration(hours: 1),
      pauseFor: const Duration(minutes: 3),
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
    _ingest(result.recognizedWords);
  }

  /// Merges a new speech-engine hypothesis into the running
  /// candidate plate instead of treating each result — or each
  /// engine restart — as its own independent reading.
  /// ---------------------------------------------------------------
  /// Why this exists: Android's on-device recognizer segments a
  /// continuous dictation into multiple separate "final" results
  /// even with a long pauseFor configured (this is a real-device
  /// behavior, not something the pauseFor/listenFor values in
  /// _listenOnce fully control) — a genuinely long dictation
  /// restarts the recognizer several times mid-plate. Committing on
  /// every one of those was the exact bug that showed a single
  /// spoken plate as several separate table rows with the digits
  /// growing longer each time ("7", then "77", then "7742") — each
  /// restart's fragment was being logged as if it were already a
  /// complete, final plate.
  ///
  /// Instead: keep merging new fragments into [_candidateLetters]/
  /// [_candidateDigits] across as many restarts as it takes, and
  /// only commit once nothing new has arrived for [_settleDuration]
  /// — that's the one and only commit trigger now (see
  /// _commitCandidateIfComplete). The engine's own finalResult flag
  /// is deliberately ignored for this decision; it fires too
  /// eagerly/inconsistently on-device to be trusted here.
  void _ingest(String rawText) {
    if (rawText.trim().isEmpty) return;
    final token = _normalizer.normalize(rawText);
    if (token.letters.isEmpty && token.digits.isEmpty) return;

    final sameDigitSequenceContinuing =
        _candidateDigits.isNotEmpty && token.digits.startsWith(_candidateDigits);
    final digitsConflict = token.digits.isNotEmpty &&
        _candidateDigits.isNotEmpty &&
        !sameDigitSequenceContinuing &&
        !token.digits.startsWith(_candidateDigits);

    if (digitsConflict) {
      // The new fragment's digits don't extend what we already had
      // — the operator has moved on to a new plate. Commit whatever
      // candidate we were building (only takes effect if it was
      // actually complete) before starting fresh.
      _commitCandidateIfComplete();
    }

    if (token.letters.isNotEmpty) _candidateLetters = token.letters;
    if (token.digits.isNotEmpty) _candidateDigits = token.digits;

    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDuration, _commitCandidateIfComplete);
  }

  /// The single commit path — called only after [_settleDuration]
  /// of true silence (no further fragments merged in), or when a
  /// digit conflict signals a new plate has started. Always clears
  /// the candidate, whether or not it ends up complete enough to
  /// emit, so a garbled/partial reading can't linger and get
  /// silently merged into whatever the operator says next.
  void _commitCandidateIfComplete() {
    _settleTimer?.cancel();
    if (_candidateLetters.isEmpty && _candidateDigits.isEmpty) return;

    final letters = _candidateLetters;
    final digits = _candidateDigits;
    _candidateLetters = '';
    _candidateDigits = '';

    final token = PlateToken(
      letters: letters,
      digits: digits,
      raw: '$letters $digits'.trim(),
    );
    if (!token.isComplete()) return;

    _plateController.add(
      PlateDetection(token: token, detectedAt: DateTime.now()),
    );
  }

  /// Pauses recognition without tearing down the engine session —
  /// used while the "لوحة مطلوبة" alert modal is on screen so the
  /// mic doesn't pick up the alarm sound / operator speech as
  /// plate input. Discards (doesn't commit) any in-flight candidate
  /// — a pause here always follows a just-committed complete plate
  /// triggering the alert, never a mid-utterance interruption.
  Future<void> pause() async {
    if (_status != SpeechServiceStatus.listening) return;
    _updateStatus(SpeechServiceStatus.paused);
    _settleTimer?.cancel();
    _candidateLetters = '';
    _candidateDigits = '';
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
    _settleTimer?.cancel();
    _candidateLetters = '';
    _candidateDigits = '';
    await _speech.stop();
    _updateStatus(SpeechServiceStatus.idle);
  }

  void _handleEngineStatus(String platformStatus) {
    // speech_to_text auto-stops after `listenFor`/`pauseFor` elapses
    // (or the OS enforces its own internal cap regardless of what
    // we requested). Re-arm immediately unless the operator
    // explicitly stopped/paused the session or the engine is in an
    // error/unavailable state — this is what makes "بدء" behave as
    // "stays open until I press إيقاف" instead of silently dying
    // after the first OS-level timeout.
    if (platformStatus == 'done' || platformStatus == 'notListening') {
      _maybeRestart();
    }
  }

  /// Restarts listening if the session is still meant to be active.
  /// A short settle delay avoids a known platform quirk: calling
  /// listen() again in the exact same tick as the previous session's
  /// 'done'/'notListening' callback can be silently dropped on some
  /// Android OEM builds, which is what used to make the mic look
  /// like it "closed" without the operator ever pressing إيقاف.
  void _maybeRestart() {
    if (!_sessionActive) return;
    if (_status == SpeechServiceStatus.paused) return;
    if (_status == SpeechServiceStatus.error) return;
    if (_status == SpeechServiceStatus.unavailable) return;

    Timer(const Duration(milliseconds: 200), () {
      if (_sessionActive && _status != SpeechServiceStatus.paused) {
        _listenOnce();
      }
    });
  }

  void _handleEngineError(SpeechRecognitionError error) {
    // Permanent errors (e.g. permission denied, engine missing)
    // surface as unavailable; transient errors just re-arm.
    if (error.permanent) {
      _sessionActive = false;
      _updateStatus(SpeechServiceStatus.error);
      return;
    }
    _maybeRestart();
  }

  void _updateStatus(SpeechServiceStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void dispose() {
    _settleTimer?.cancel();
    _statusController.close();
    _plateController.close();
    _audioLevelController.close();
    _speech.cancel();
  }
}
