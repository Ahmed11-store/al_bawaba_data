import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/plate_record.dart';
import '../services/blacklist_sync_service.dart';
import '../services/database_service.dart';

/// Browse the imported "wanted plates" blacklist itself. Before
/// this screen existed, an operator who imported a file could only
/// see a count on the "الكل" tab — the actual plate rows they just
/// uploaded were never rendered anywhere in the app.
class BlacklistScreen extends StatefulWidget {
  const BlacklistScreen({super.key});

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  late Future<List<PlateRecord>> _future;
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.instance.getBlacklist();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      setState(() {
        _future = DatabaseService.instance.getBlacklist(search: value);
      });
    });
  }

  /// Manual on-demand pull — the automatic sync already runs on
  /// every app launch (see app_gate.dart); this is just for testing
  /// or when the operator doesn't want to wait for the next open.
  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final result = await BlacklistSyncService.instance.syncIfNeeded();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _future = DatabaseService.instance.getBlacklist();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.updated
              ? 'تم التحديث: ${result.recordCount} لوحة.'
              : 'مفيش تحديث جديد حاليًا.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اللوحات المطلوبة المستوردة'),
          actions: [
            IconButton(
              tooltip: 'تحديث الآن',
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'ابحث بالحروف أو الأرقام...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<PlateRecord>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final records = snapshot.data ?? [];
                  if (records.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد لوحات مطابقة',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = records[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Text(
                              r.displayPlate,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            if (r.bankName.isNotEmpty)
                              Flexible(
                                child: Text(
                                  r.bankName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary),
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
          ],
        ),
      ),
    );
  }
}
