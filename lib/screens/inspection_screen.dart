import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../models/plate_record.dart';
import '../providers/inspection_provider.dart';
import '../services/database_service.dart';
import '../services/import_export_service.dart';
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
  bool _exporting = false;
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

  /// Saves everything read out during this session to a local CSV
  /// file and opens the share sheet so the operator can keep it on
  /// the phone (Files app, Drive, WhatsApp to themselves, etc.) —
  /// separate from the "الكل" tab's export, which covers the full
  /// historical log rather than just what's on screen right now.
  Future<void> _exportSession() async {
    if (_exporting) return;
    final logs = context.read<InspectionProvider>().sessionLog;
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مفيش نتائج في الجلسة الحالية لحفظها')),
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      await ImportExportService().exportLogsToCsv(
        logs,
        fileName: 'جلسة_فحص',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('البوابة - الفحص'),
          actions: [
            IconButton(
              tooltip: 'حفظ نتائج الجلسة في ملف',
              onPressed: _exporting ? null : _exportSession,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded),
            ),
          ],
        ),
        body: const Column(
          children: [
            _StatusHeader(),
            _EngineErrorBanner(),
            _ModeToggleRow(),
            _BlacklistPanel(),
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

/// Previously: if speech recognition failed to start (no offline
/// Arabic language pack installed, mic permission denied/missing
/// from AndroidManifest.xml, or the platform engine unavailable for
/// any other reason), the "بدء" button would just silently revert
/// to its idle state with zero explanation — indistinguishable from
/// a broken microphone from the operator's point of view. This
/// banner surfaces the actual cause so "بدء ومحصلش حاجة" stops
/// being a silent failure.
class _EngineErrorBanner extends StatelessWidget {
  const _EngineErrorBanner();

  @override
  Widget build(BuildContext context) {
    return Selector<InspectionProvider, SpeechServiceStatus>(
      selector: (_, p) => p.status,
      builder: (context, status, _) {
        if (status != SpeechServiceStatus.unavailable &&
            status != SpeechServiceStatus.error) {
          return const SizedBox.shrink();
        }

        final message = status == SpeechServiceStatus.unavailable
            ? 'التعرف الصوتي أوفلاين مش متاح على الجهاز ده. الأسباب الشائعة: '
                '(١) حزمة اللغة العربية للتعرف الصوتي أوفلاين مش منزّلة '
                '(الإعدادات ← Google ← Voice ← On-device recognition ← نزّل العربية)، '
                'أو (٢) إذن الميكروفون مرفوض للتطبيق '
                '(إعدادات الجهاز ← التطبيقات ← البوابة ← الأذونات ← فعّل الميكروفون).'
            : 'حصل خطأ في محرك التعرف الصوتي أثناء الاستماع. جرّب تدوس "بدء" تاني، '
                'ولو المشكلة استمرت راجع إذن الميكروفون وحزمة اللغة العربية.';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.danger.withOpacity(0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.textPrimary, height: 1.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lets the operator see the imported "wanted plates" list directly
/// on the Inspection screen, not only in a separate tab. Collapsed
/// by default (the table can hold thousands of rows and this
/// screen's main job is the live scan session, not browsing the
/// blacklist) — tap to expand and search.
class _BlacklistPanel extends StatefulWidget {
  const _BlacklistPanel();

  @override
  State<_BlacklistPanel> createState() => _BlacklistPanelState();
}

class _BlacklistPanelState extends State<_BlacklistPanel> {
  bool _expanded = false;
  Future<List<PlateRecord>>? _future;
  Timer? _debounce;
  final _searchController = TextEditingController();

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded && _future == null) {
        _future = DatabaseService.instance.getBlacklist();
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() {
        _future = DatabaseService.instance.getBlacklist(search: value);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.storage_rounded,
                      color: AppColors.accentBlue, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('اللوحات المطلوبة المستوردة',
                        style: TextStyle(color: AppColors.textPrimary)),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: AppColors.cardBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'ابحث بالحروف أو الأرقام...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: FutureBuilder<List<PlateRecord>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final records = snapshot.data ?? [];
                  if (records.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'لا توجد لوحات مطابقة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: records.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.cardBorder, height: 1),
                    itemBuilder: (context, i) {
                      final r = records[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              r.displayPlate,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (r.bankName.isNotEmpty)
                              Flexible(
                                child: Text(
                                  r.bankName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
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
          SizedBox(width: 28), // aligns with the ✓/✗ icon in each row
          SizedBox(width: 26, child: Text('#', style: style)),
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
