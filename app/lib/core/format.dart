import 'package:intl/intl.dart';

String formatIqd(int amount, String locale) =>
    NumberFormat.decimalPattern(locale == 'ar' ? 'ar' : 'en').format(amount);

String formatDateTime(DateTime t, String locale) =>
    DateFormat.yMMMd(locale).add_jm().format(t);

String formatTime(DateTime t, String locale) => DateFormat.jm(locale).format(t);

/// Accepts what Iraqi users actually type ("0770 123 4567", "770...",
/// "+964 770...", "00964...") and returns +9647XXXXXXXXX, or null.
String? normalizeIraqiMobile(String input) {
  var d = latinDigits(input).replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00964')) d = d.substring(5);
  if (d.startsWith('964')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  if (!RegExp(r'^7[0-9]{9}$').hasMatch(d)) return null;
  return '+964$d';
}

/// Arabic-Indic (٠١٢…) and Persian (۰۱۲…) digits → 0-9.
String latinDigits(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final out = StringBuffer();
  for (final ch in input.split('')) {
    final a = arabic.indexOf(ch);
    final p = persian.indexOf(ch);
    out.write(a >= 0 ? '$a' : (p >= 0 ? '$p' : ch));
  }
  return out.toString();
}

/// Any international number in +E.164 form, for staff sign-up.
String? normalizeInternationalPhone(String input) {
  final iraqi = normalizeIraqiMobile(input);
  if (iraqi != null) return iraqi;
  final d = latinDigits(input).replaceAll(RegExp(r'[\s\-()]'), '');
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(d) ? d : null;
}
