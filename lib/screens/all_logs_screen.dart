import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/scan_log.dart';
import '../services/database_service.dart';
import '../services/import_export_service.dart';
import '../widgets/plate_data_table.dart';
import 'blacklist_screen.dart';

class AllLogsScreen extends StatefulWidget {
  const AllLogsScreen({super.key});

  @override
  State<AllLogsScreen> createState() => _AllLogsScreenState();
}

class _AllLogsScreenState extends State<AllLogsScreen> {
  late Future<List<ScanLog>> _future;
  final _importExport = ImportExportService();
  bool _exporting = false;
  bool _importing = false;
  int _blacklistCount = 0;

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.instance.getRecentLogs(hours: 48);
    _loadBlacklistCount();
  }

  Future<void> _loadBlacklistCount() async {
    final count = await DatabaseService.instance.blacklistCount();
    if (mounted) setState(() => _blacklistCount = count);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = DatabaseService.instance.getRecentLogs(hours: 48);
    });
    await _future;
    await _loadBlacklistCount();
  }

  Future<void> _export(List<ScanLog> logs) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await _importExport.exportLogsToCsv(logs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تصدير السجلات بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تصدير السجلات: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Bound to the new "استيراد" (import) button: opens the native
  /// file picker restricted to CSV/JSON, parses the chosen local
  /// file, then — if the blacklist already has data — asks whether
  /// to replace it entirely or append the new rows on top.
  Future<void> _importBlacklist() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await _importExport.pickAndParseBlacklistFile();
      if (result == null) {
        // Operator cancelled the picker — no message needed.
        return;
      }
      if (result.records.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'لم يتم العثور على صفوف صالحة في الملف. تأكد أن الأعمدة تحتوي على الحروف والأرقام على الأقل.',
              ),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final existingCount = await DatabaseService.instance.blacklistCount();
      bool replace = true;
      if (existingCount > 0 && mounted) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AppColors.card,
              title: const Text('توجد بيانات محفوظة بالفعل'),
              content: Text(
                'يوجد حاليًا $existingCount لوحة مسجلة. هل تريد استبدالها بالكامل بالملف الجديد (${result.records.length} لوحة)، أم إضافة اللوحات الجديدة فوق الموجودة؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إضافة فوق الموجود'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'استبدال بالكامل',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        );
        if (choice == null) return; // dialog dismissed
        replace = choice;
      }

      if (replace) {
        await DatabaseService.instance.replaceBlacklist(result.records);
      } else {
        await DatabaseService.instance.appendBlacklist(result.records);
      }

      await _loadBlacklistCount();

      if (mounted) {
        final skippedMsg =
            result.skippedRows > 0 ? ' (تم تجاهل ${result.skippedRows} صف غير صالح)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم استيراد ${result.records.length} لوحة بنجاح$skippedMsg',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر استيراد الملف: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('السجل الكامل - آخر 48 ساعة'),
          actions: [
            IconButton(
              tooltip: 'استيراد أرقام اللوحات',
              icon: _importing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              onPressed: _importing ? null : _importBlacklist,
            ),
            FutureBuilder<List<ScanLog>>(
              future: _future,
              builder: (context, snapshot) {
                final logs = snapshot.data ?? [];
                return IconButton(
                  tooltip: 'تنزيل',
                  icon: _exporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  onPressed: logs.isEmpty ? null : () => _export(logs),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            InkWell(
              onTap: _blacklistCount == 0
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BlacklistScreen(),
                        ),
                      );
                      // The operator may have imported more plates
                      // from within the browse screen in the future,
                      // or just wants the count re-checked.
                      await _loadBlacklistCount();
                    },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storage_rounded,
                        color: AppColors.accentBlue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'عدد اللوحات المطلوبة المحمّلة محليًا: $_blacklistCount'
                        '${_blacklistCount > 0 ? ' (اضغط للعرض)' : ''}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _importing ? null : _importBlacklist,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة أرقام اللوحات'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<ScanLog>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final logs = snapshot.data ?? [];
                    return PlateDataTable(logs: logs);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
