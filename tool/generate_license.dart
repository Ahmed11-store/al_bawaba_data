// أداة توليد أكواد التفعيل — تتشغّل على جهازك انت فقط، مش جزء من
// التطبيق اللي بينزل عند العميل (مش موجودة في lib/ فمش بتتحط جوه
// الـ APK).
//
// الاستخدام:
//   dart run tool/generate_license.dart <كود الجهاز> <عدد الأيام>
//
// مثال (اشتراك شهري = 30 يوم):
//   dart run tool/generate_license.dart 3F2A9B10 30
//
// كود الجهاز بتاخده من العميل — هو اللي شايفه على شاشة "تفعيل" في
// التطبيق (8 حروف/أرقام).
//
// شغّل `dart pub get` مرة واحدة في مجلد المشروع الأساسي قبل أول
// استخدام لو لسه ما شغلتش `flutter pub get`.

import 'dart:convert';
import 'dart:io';

import 'package:al_bawaba/core/base32_codec.dart';
import 'package:al_bawaba/core/license_secret.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stdout.writeln(
        'الاستخدام: dart run tool/generate_license.dart <كود الجهاز> <عدد الأيام>');
    stdout.writeln('مثال:      dart run tool/generate_license.dart 3F2A9B10 30');
    exit(1);
  }

  final deviceCode = args[0].trim().toUpperCase();
  if (deviceCode.length != 8 || !RegExp(r'^[0-9A-F]{8}$').hasMatch(deviceCode)) {
    stderr.writeln(
        'خطأ: كود الجهاز لازم يكون 8 حروف/أرقام hex بالظبط (زي اللي ظاهر عند العميل في شاشة "تفعيل").');
    exit(1);
  }

  final days = int.tryParse(args[1].trim());
  if (days == null || days <= 0) {
    stderr.writeln('خطأ: عدد الأيام لازم يكون رقم صحيح أكبر من صفر.');
    exit(1);
  }

  final deviceBytes = List<int>.generate(
    4,
    (i) => int.parse(deviceCode.substring(i * 2, i * 2 + 2), radix: 16),
  );

  final expiryDate = DateTime.now().toUtc().add(Duration(days: days));
  final expiryDay = expiryDate.difference(kLicenseEpoch).inDays;
  if (expiryDay < 0 || expiryDay > 0xFFFF) {
    stderr.writeln('خطأ: تاريخ الانتهاء برة المدى المسموح به.');
    exit(1);
  }

  final payload = <int>[
    ...deviceBytes,
    (expiryDay >> 8) & 0xFF,
    expiryDay & 0xFF,
  ];

  final hmac = Hmac(sha256, utf8.encode(kLicenseSecret));
  final signature = hmac.convert(payload).bytes.sublist(0, 4);

  final codeBytes = [...payload, ...signature];
  final encoded = base32Encode(codeBytes);

  final grouped = <String>[];
  for (var i = 0; i < encoded.length; i += 4) {
    final end = (i + 4 > encoded.length) ? encoded.length : i + 4;
    grouped.add(encoded.substring(i, end));
  }

  stdout.writeln('');
  stdout.writeln('كود جهاز العميل : $deviceCode');
  stdout.writeln('صالح لمدة        : $days يوم');
  stdout.writeln(
      'ينتهي تقريبًا في : ${expiryDate.toLocal().toIso8601String().split("T").first}');
  stdout.writeln('');
  stdout.writeln('كود التفعيل (ابعته للعميل):');
  stdout.writeln(grouped.join('-'));
  stdout.writeln('');

  if (kLicenseSecret.startsWith('CHANGE-ME')) {
    stderr.writeln(
        'تحذير: لسه مستخدم الـ secret الافتراضي في lib/core/license_secret.dart — '
        'غيّره لقيمة عشوائية خاصة بيك قبل ما تبيع أي اشتراك فعلي.');
  }
}
