/// Audio Alert Handling Service (Offline)
/// ---------------------------------------------------------------
/// Owns the "لوحة مطلوبة" (wanted-plate) alert lifecycle:
///   1. Pause the speech listener.
///   2. Play a bundled local buzzer/alarm asset (never streamed).
///   3. Trigger haptic vibration for outdoor/noisy-environment
///      feedback in parallel with audio.
///   4. Expose a dismiss() that resumes the STT session.
///
/// Fully offline: audio playback is from a bundled asset
/// (`assets/audio/wanted_alert.wav`) via `audioplayers`, which
/// plays local files with no network access. Vibration uses the
/// `vibration` package (device haptics only).
///
/// pubspec.yaml dependencies this file assumes:
///   audioplayers: ^6.0.0
///   vibration: ^2.0.0
///
/// pubspec.yaml assets entry:
///   assets:
///     - assets/audio/wanted_alert.wav
library audio_alert_service;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

import 'speech_recognition_service.dart';

/// Vibration pattern (ms): wait, vibrate, pause, vibrate... —
/// three short urgent pulses rather than one long buzz, so it
/// reads as "alert" rather than "notification".
const List<int> kWantedPlateVibrationPattern = [0, 250, 120, 250, 120, 250];

class AudioAlertService {
  AudioAlertService({
    required SpeechRecognitionService speechService,
    AudioPlayer? player,
  })  : _speechService = speechService,
        _player = player ?? AudioPlayer();

  final SpeechRecognitionService _speechService;
  final AudioPlayer _player;

  static const String _alertAssetPath = 'audio/wanted_alert.wav';

  bool _alertActive = false;
  bool get isAlertActive => _alertActive;

  final StreamController<bool> _alertActiveController =
      StreamController<bool>.broadcast();

  /// Emits true when an alert modal should be shown, false when
  /// it should be dismissed. The UI layer's BLoC/Provider should
  /// subscribe to this to drive the Alert Modal visibility rather
  /// than managing that state itself, so audio/vibration/pause
  /// and the modal never drift out of sync.
  Stream<bool> get alertActiveStream => _alertActiveController.stream;

  Future<void> _prepare() async {
    // AssetSource plays directly from the app bundle — no network
    // I/O is possible through this code path.
    await _player.setSource(AssetSource(_alertAssetPath));
    await _player.setReleaseMode(ReleaseMode.loop);
  }

  bool _prepared = false;

  /// Fires the full "تم رصد لوحة مطلوبة" alert sequence. Call this
  /// the moment the blacklist DB match returns a hit — before the
  /// UI even finishes building the modal — so audio/vibration/mic
  /// pause happen with minimum latency after detection.
  Future<void> triggerWantedPlateAlert() async {
    if (_alertActive) return; // avoid overlapping alerts
    _alertActive = true;
    _alertActiveController.add(true);

    // 1. Pause the speech listener immediately so the alarm sound
    //    and any operator speech during the alert aren't picked
    //    back up as plate input.
    await _speechService.pause();

    // 2 & 3. Play the local buzzer asset and vibrate, in parallel.
    unawaited(_playAlarmLoop());
    unawaited(_vibrateAlert());
  }

  Future<void> _playAlarmLoop() async {
    try {
      if (!_prepared) {
        await _prepare();
        _prepared = true;
      }
      await _player.resume();
    } catch (_) {
      // Asset missing or codec unsupported on this device — fail
      // silently on audio so the visual alert modal (handled by
      // the UI layer independently of this service) still gets
      // shown; vibration is the fallback alert channel.
    }
  }

  Future<void> _vibrateAlert() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    final hasCustom = await Vibration.hasCustomVibrationsSupport();
    if (hasCustom == true) {
      await Vibration.vibrate(pattern: kWantedPlateVibrationPattern);
    } else {
      // Devices without custom pattern support: three discrete
      // vibrate calls approximating the same rhythm.
      for (final _ in [0, 1, 2]) {
        await Vibration.vibrate(duration: 250);
        await Future.delayed(const Duration(milliseconds: 370));
      }
    }
  }

  /// Called when the operator taps the red "إغلاق" (close) button
  /// on the Alert Modal. Stops audio/vibration and resumes the
  /// offline voice listener.
  Future<void> dismiss() async {
    if (!_alertActive) return;

    await _player.stop();
    Vibration.cancel();

    _alertActive = false;
    _alertActiveController.add(false);

    await _speechService.resume();
  }

  void dispose() {
    _alertActiveController.close();
    _player.dispose();
  }
}
