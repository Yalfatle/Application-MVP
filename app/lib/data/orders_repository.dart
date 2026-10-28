import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/cache.dart';
import '../core/errors.dart';
import 'models.dart';

enum BookingResult { sent, queued }

class OrdersRepository {
  OrdersRepository(this.cache);
  final LocalCache cache;
  SupabaseClient get _db => Supabase.instance.client;

  static const _cols =
      'id,patient_id,lab_id,package_id,package_name_ar,package_name_en,price_iqd,commission_iqd,status,'
      'location_lat,location_lng,location_note,runner_id,status_reason,created_at';
  static const _queueKey = 'user:pending_orders';

  // ---------------------------------------------------------------- booking

  /// Books a test. If the connection is down, the booking is kept on the
  /// phone and sent automatically later. A client-generated id makes
  /// retries safe: the server never creates the same booking twice.
  Future<BookingResult> book({
    required Lab lab,
    required LabPackage package,
    required double lat,
    required double lng,
    String? note,
  }) async {
    final payload = {
      'client_request_id': const Uuid().v4(),
      'package_id': package.id,
      'location_lat': lat,
      'location_lng': lng,
      if (note != null && note.trim().isNotEmpty) 'location_note': note.trim(),
    };
    try {
      await _send(payload);
      return BookingResult.sent;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final queue = _queue()
        ..add({
          'payload': payload,
          'lab_id': lab.id,
          'package_name_ar': package.nameAr,
          'package_name_en': package.nameEn,
          'price_iqd': package.priceIqd,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      await cache.write(_queueKey, queue);
      return BookingResult.queued;
    }
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    try {
      await _db.from('orders').insert(payload).timeout(const Duration(seconds: 20));
    } on PostgrestException catch (e) {
      if (e.code == '23505') return; // already delivered by an earlier retry
      rethrow;
    }
  }

  List<Map<String, dynamic>> _queue() =>
      (cache.read<List<dynamic>>(_queueKey) ?? []).cast<Map<String, dynamic>>().toList();

  bool get hasQueued => _queue().isNotEmpty;

  /// Bookings still waiting for a connection, shown in "My bookings".
  List<LabOrder> queuedOrders(String patientId) => _queue().map((q) {
        final p = q['payload'] as Map<String, dynamic>;
        return LabOrder(
          id: p['client_request_id'] as String,
          patientId: patientId,
          labId: q['lab_id'] as String,
          packageId: p['package_id'] as String?,
          packageNameAr: q['package_name_ar'] as String,
          packageNameEn: q['package_name_en'] as String,
          priceIqd: (q['price_iqd'] as num).toInt(),
          status: OrderStatus.pending,
          lat: (p['location_lat'] as num).toDouble(),
          lng: (p['location_lng'] as num).toDouble(),
          locationNote: p['location_note'] as String?,
          createdAt: DateTime.parse(q['created_at'] as String).toLocal(),
          queued: true,
        );
      }).toList();

  /// Try to deliver queued bookings. Returns how many went through.
  Future<int> flushQueue() async {
    final queue = _queue();
    if (queue.isEmpty) return 0;
    var sent = 0;
    final remaining = <Map<String, dynamic>>[];
    for (final q in queue) {
      try {
        await _send(q['payload'] as Map<String, dynamic>);
        sent++;
      } catch (e) {
        // Keep it for next time unless the server rejected it outright
        // (e.g. the test was removed); then drop it.
        if (isNetworkError(e)) remaining.add(q);
      }
    }
    await cache.write(_queueKey, remaining);
    return sent;
  }

  // ---------------------------------------------------------------- patient

  List<LabOrder>? cachedMyOrders() => cache
      .read<List<dynamic>>('user:orders')
      ?.map((e) => LabOrder.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<List<LabOrder>> fetchMyOrders(String patientId) async {
    final rows = await _db
        .from('orders')
        .select(_cols)
        .eq('patient_id', patientId)
        .order('created_at', ascending: false)
        .limit(100);
    final orders = rows.map(LabOrder.fromJson).toList();
    await cache.write('user:orders', orders.map((o) => o.toJson()).toList());
    return orders;
  }

  /// Live updates for one order (status changes, runner assignment).
  Stream<LabOrder?> watchOrder(String id) => _db
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : LabOrder.fromJson(rows.first));

  Future<LabOrder> fetchOrder(String id) async =>
      LabOrder.fromJson(await _db.from('orders').select(_cols).eq('id', id).single());

  Future<List<OrderEvent>> fetchEvents(String orderId) async {
    final rows = await _db
        .from('order_events')
        .select('to_status,created_at,note')
        .eq('order_id', orderId)
        .order('created_at');
    return rows.map(OrderEvent.fromJson).toList();
  }

  Stream<RunnerLocation?> watchRunner(String orderId) => _db
      .from('runner_locations')
      .stream(primaryKey: ['order_id'])
      .eq('order_id', orderId)
      .map((rows) => rows.isEmpty ? null : RunnerLocation.fromJson(rows.first));

  Future<String?> personName(String userId) async {
    final row = await _db.from('profiles').select('full_name').eq('id', userId).maybeSingle();
    return row?['full_name'] as String?;
  }

  // ---------------------------------------------------------------- lab side

  /// Live list of a lab's orders.
  Stream<List<LabOrder>> watchLabOrders(String labId) => _db
      .from('orders')
      .stream(primaryKey: ['id'])
      .eq('lab_id', labId)
      .order('created_at', ascending: false)
      .limit(300)
      .map((rows) => rows.map(LabOrder.fromJson).toList());

  Future<List<LabOrder>> fetchPatientOrders(String patientId, {String? labId}) async {
    var q = _db.from('orders').select(_cols).eq('patient_id', patientId);
    if (labId != null) q = q.eq('lab_id', labId);
    final rows = await q.order('created_at', ascending: false);
    return rows.map(LabOrder.fromJson).toList();
  }

  Future<void> setStatus(String orderId, OrderStatus status, {String? reason}) =>
      _db.rpc('update_order_status', params: {
        'p_order_id': orderId,
        'p_status': status.db,
        'p_reason': reason,
      });

  Future<void> assignRunner(String orderId, String runnerId) =>
      _db.rpc('assign_runner', params: {'p_order_id': orderId, 'p_runner_id': runnerId});

  Future<void> sendRunnerLocation(String orderId, double lat, double lng, {double? heading, double? accuracy}) =>
      _db.rpc('update_runner_location', params: {
        'p_order_id': orderId,
        'p_lat': lat,
        'p_lng': lng,
        'p_heading': heading,
        'p_accuracy': accuracy,
      });

  /// Everyone who has booked with this lab, most recent first,
  /// with the date of their latest booking.
  Future<List<(String patientId, DateTime lastBooking)>> labPatients(String labId) async {
    final rows = await _db
        .from('orders')
        .select('patient_id,created_at')
        .eq('lab_id', labId)
        .order('created_at', ascending: false)
        .limit(2000);
    final seen = <String>{};
    final out = <(String, DateTime)>[];
    for (final r in rows) {
      final id = r['patient_id'] as String;
      if (seen.add(id)) out.add((id, DateTime.parse(r['created_at'] as String).toLocal()));
    }
    return out;
  }

  /// Names of patients who booked with the lab (no phone numbers, ever).
  Future<Map<String, String>> patientNames(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows = await _db.from('profiles').select('id,full_name').inFilter('id', list);
    return {for (final r in rows) r['id'] as String: (r['full_name'] as String?) ?? ''};
  }
}
