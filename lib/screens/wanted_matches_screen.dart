import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../models/scan_log.dart';
import '../services/database_service.dart';

class WantedMatchesScreen extends StatefulWidget {
  const WantedMatchesScreen({super.key});

  @override
  State<WantedMatchesScreen> createState() => _WantedMatchesScreenState();
}

class _WantedMatchesScreenState extends State<WantedMatchesScreen> {
  late Future<List<ScanLog>> _future;

  @override
  void initState() {
    super.initState();
    _future = DatabaseService.instance.getWantedLogs();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = DatabaseService.instance.getWantedLogs();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سجل المطابقات - مطلوبة')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<ScanLog>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text(
                          'لا توجد لوحات مطلوبة مسجلة',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: logs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _WantedCard(log: logs[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WantedCard extends StatelessWidget {
  const _WantedCard({required this.log});
  final ScanLog log;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.danger, size: 22),
              const SizedBox(width: 8),
              Text(
                log.displayPlate,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _formatTimestamp(log.timestamp),
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const Divider(color: AppColors.cardBorder, height: 20),
          _DetailLine(label: 'البنك', value: log.matchedBankName ?? '—'),
          _DetailLine(
              label: 'نوع المركبة', value: log.matchedVehicleModel ?? '—'),
          _DetailLine(
              label: 'رقم الشاسيه', value: log.matchedChassisNumber ?? '—'),
          if (log.hasLocation) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () async {
                final uri = Uri.parse(log.googleMapsUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.map_outlined, color: AppColors.accentBlue),
              label: const Text('فتح الموقع في خرائط جوجل',
                  style: TextStyle(color: AppColors.accentBlue)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
