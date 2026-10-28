import 'package:app/core/format.dart';
import 'package:app/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Iraqi mobile numbers', () {
    test('accepts the ways people actually type them', () {
      for (final input in [
        '07701234567',
        '0770 123 4567',
        '770-123-4567',
        '+964 770 123 4567',
        '009647701234567',
        '9647701234567',
        '٠٧٧٠١٢٣٤٥٦٧', // Arabic-Indic digits
      ]) {
        expect(normalizeIraqiMobile(input), '+9647701234567', reason: input);
      }
    });

    test('rejects landlines and junk', () {
      for (final input in ['', '123', '0123456789', '+44 7700 900123', '0770123456']) {
        expect(normalizeIraqiMobile(input), isNull, reason: input);
      }
    });

    test('staff can use foreign numbers too', () {
      expect(normalizeInternationalPhone('+44 7700 900123'), '+447700900123');
      expect(normalizeInternationalPhone('0770 123 4567'), '+9647701234567');
      expect(normalizeInternationalPhone('hello'), isNull);
    });
  });

  group('roles', () {
    test('hierarchy: each role includes those below it', () {
      expect(UserRole.superAdmin.atLeast(UserRole.labAdmin), isTrue);
      expect(UserRole.labAdmin.atLeast(UserRole.runner), isTrue);
      expect(UserRole.runner.atLeast(UserRole.clerk), isTrue);
      expect(UserRole.clerk.atLeast(UserRole.runner), isFalse);
      expect(UserRole.patient.atLeast(UserRole.clerk), isFalse);
    });

    test('parses database values', () {
      expect(UserRole.parse('lab_admin'), UserRole.labAdmin);
      expect(UserRole.parse('nonsense'), UserRole.patient);
      expect(OrderStatus.parse('sample_taken'), OrderStatus.sampleTaken);
    });
  });

  group('orders', () {
    final json = {
      'id': 'o1',
      'patient_id': 'p1',
      'lab_id': 'l1',
      'package_id': 'k1',
      'package_name_ar': 'فحص',
      'package_name_en': 'Checkup',
      'price_iqd': 10000,
      'commission_iqd': 1500,
      'status': 'on_way',
      'location_lat': 33.3128,
      'location_lng': 44.3614,
      'location_note': 'green door',
      'runner_id': 'r1',
      'status_reason': null,
      'created_at': '2026-10-28T10:00:00Z',
    };

    test('round-trips through the offline cache', () {
      final o = LabOrder.fromJson(json);
      final back = LabOrder.fromJson(o.toJson());
      expect(back.status, OrderStatus.onWay);
      expect(back.priceIqd, 10000);
      expect(back.locationNote, 'green door');
      expect(back.packageName('ar'), 'فحص');
    });

    test('gives runners a plain Google Maps link', () {
      final o = LabOrder.fromJson(json);
      expect(o.mapsLink, 'https://www.google.com/maps/search/?api=1&query=33.3128,44.3614');
      expect(o.directionsLink, contains('destination=33.3128,44.3614'));
    });
  });
}
