import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../providers/inspection_provider.dart';
import '../services/speech_recognition_service.dart';
import '../widgets/audio_level_meter.dart';
import '../widgets/plate_data_table.dart';
import '../widgets/wanted_alert_modal.dart';

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  bool _alertDialogShowing = false;
  StreamSubscription<bool>? _alertSub;

  @override
  void initState() {
    super.initState();
    // initState runs exactly once per widget lifetime — unlike
    // didChangeDependencies, which Flutter can call again later
    // (e.g. on a Theme/MediaQuery change or hot reload) and would
    // silently stack a second, third, ... listener on this stream,
    // eventually opening duplicate alert dialogs. Subscribing here
    // and cancelling in dispose() guarantees exactly one listener.
    final provider = context.read<InspectionProvider>();
    _alertSub = provider.alertActiveStream.listen((active) {
      if (!mounted) return;
      if (active && !_alertDialogShowing) {
        _alertDialogShowing = true;
        WantedAlertModal.show(context).then((_) {
          _alertDialogShowing = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('البوابة - الفحص')),
        body: const Column(
          children: [
            _StatusHeader(),
            _ModeToggleRow(),
            _AudioLevelRow(),
            Divider(color: AppColors.cardBorder, height: 1),
            _TableHeader(),
            Expanded(child: _SessionTable()),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds only when [InspectionProvider.isSessionActive] /
/// `.status` changes (session start/stop) — not on every audio
/// tick, which fires far more often while listening.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader();

  @override
  Widget build(BuildContext context) {
    return Selector<InspectionProvider, (bool, bool)>(
      selector: (_, p) => (
        p.isSessionActive,
        p.status == SpeechServiceStatus.listening,
      ),
      builder: (context, data, _) {
        final (isActive, isListening) = data;
        final provider = context.read<InspectionProvider>();

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isListening ? AppColors.success : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isActive ? 'بدء الجلسة الصوتية' : 'إيقاف الجلسة الصوتية',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isActive ? AppColors.danger : AppColors.accentBlue,
                ),
                onPressed: () async {
                  if (isActive) {
                    await provider.stopSession();
                  } else {
                    await provider.startSession();
                  }
                },
                child: Text(isActive ? 'إيقاف' : 'بدء'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rebuilds only when `.mode` changes (an infrequent, explicit tap).
class _ModeToggleRow extends StatelessWidget {
  const _ModeToggleRow();

  @override
  Widget build(BuildContext context) {
    return Selector<InspectionProvider, InspectionMode>(
      selector: (_, p) => p.mode,
      builder: (context, mode, _) {
        final provider = context.read<InspectionProvider>();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: 'سريع',
                  selected: mode == InspectionMode.fast,
                  onTap: () => provider.setMode(InspectionMode.fast),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeChip(
                  label: 'الموقع',
                  selected: mode == InspectionMode.gps,
                  onTap: () => provider.setMode(InspectionMode.gps),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The ONLY widget that rebuilds on every audio-level tick
/// (~10-20x/sec while listening). Isolating it here is what keeps
/// the header, mode toggle, and — most importantly — the scan
/// table from re-diffing dozens of times a second during a live
/// session.
class _AudioLevelRow extends StatelessWidget {
  const _AudioLevelRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Selector<InspectionProvider, double>(
              selector: (_, p) => p.audioLevel,
              builder: (_, level, __) => AudioLevelMeter(level: level),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('#', style: style)),
          Expanded(
              flex: 2,
              child: Text('الحروف', style: style, textAlign: TextAlign.center)),
          Expanded(
              flex: 2,
              child: Text('الأرقام', style: style, textAlign: TextAlign.center)),
          Expanded(
              flex: 2,
              child: Text('الحالة', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 36, child: Text('', style: style)),
        ],
      ),
    );
  }
}

/// Rebuilds only when the sessionLog list reference changes (a new
/// plate was detected) — not on every audio-level tick.
class _SessionTable extends StatelessWidget {
  const _SessionTable();

  @override
  Widget build(BuildContext context) {
    return Selector<InspectionProvider, int>(
      // sessionLog.length as the selector key: the provider
      // mutates the list in place then calls notifyListeners(), so
      // comparing length (which does change) is what actually
      // triggers a rebuild here — comparing the list reference
      // itself would never change since it's the same List instance.
      selector: (_, p) => p.sessionLog.length,
      builder: (context, _, __) {
        final logs = context.read<InspectionProvider>().sessionLog;
        return PlateDataTable(logs: logs);
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBlue : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accentBlue : AppColors.cardBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
