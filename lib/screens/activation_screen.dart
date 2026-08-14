import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../services/license_service.dart';

/// Shown instead of [MainNavigation] whenever the app isn't
/// currently activated (first run, or a monthly code that expired).
///
/// Flow is fully offline / out-of-app:
///   1. Operator reads the device code shown here and sends it to
///      you, along with proof of payment, outside the app
///      (WhatsApp / Vodafone Cash / InstaPay / however you invoice).
///   2. You run `dart run tool/generate_license.dart <device_code>
///      <days>` on your own machine and send back the resulting
///      activation code.
///   3. Operator types it in below — no internet needed on their
///      end at any point.
///
/// TODO before shipping: put your real WhatsApp/phone number in
/// [kSupportContactLine] below so operators know how to reach you.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({
    super.key,
    required this.status,
    required this.onActivated,
  });

  final LicenseStatus status;
  final VoidCallback onActivated;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

const String kSupportContactLine = 'للتجديد أو الاستفسار: [حط رقمك هنا]';

class _ActivationScreenState extends State<ActivationScreen> {
  final _codeController = TextEditingController();
  String? _deviceCode;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDeviceCode();
  }

  Future<void> _loadDeviceCode() async {
    final code = await LicenseService.instance.getOrCreateDeviceCode();
    if (mounted) setState(() => _deviceCode = code);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final raw = _codeController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final ok = await LicenseService.instance.activate(raw);

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      widget.onActivated();
    } else {
      setState(() {
        _errorMessage =
            'كود التفعيل غير صحيح أو غير مخصص لهذا الجهاز. تأكد إنك نسخته كامل من غير مسافات ناقصة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wasEverActivated = widget.status.expiryDate != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Icon(
                  wasEverActivated
                      ? Icons.lock_clock_rounded
                      : Icons.lock_outline_rounded,
                  color: AppColors.accentBlue,
                  size: 52,
                ),
                const SizedBox(height: 12),
                Text(
                  wasEverActivated ? 'انتهت صلاحية الاشتراك' : 'البرنامج يحتاج تفعيل',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  wasEverActivated
                      ? 'انتهى اشتراكك الشهري. جدّد الاشتراك عشان تكمل استخدام البرنامج.'
                      : 'فعّل اشتراكك الشهري عشان تقدر تستخدم البرنامج — التفعيل بيتم مرة واحدة وبعدها البرنامج يشتغل أوفلاين بالكامل لحد نهاية المدة.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  kSupportContactLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.accentBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 26),
                _Card(
                  title: '١. ابعتلنا كود الجهاز ده مع إثبات الدفع',
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _deviceCode ?? '...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'نسخ',
                        icon: const Icon(Icons.copy_rounded,
                            color: AppColors.accentBlue),
                        onPressed: _deviceCode == null
                            ? null
                            : () {
                                Clipboard.setData(
                                    ClipboardData(text: _deviceCode!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تم نسخ كود الجهاز')),
                                );
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Card(
                  title: '٢. اكتب كود التفعيل اللي هيوصلك',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _codeController,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                        decoration: InputDecoration(
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          hintStyle:
                              const TextStyle(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style:
                              const TextStyle(color: AppColors.danger, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('تفعيل'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
