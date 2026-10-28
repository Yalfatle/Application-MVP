import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/documents_list.dart';
import '../common/widgets.dart';

/// One booking: live status, live runner position, results, chat with lab.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late final Stream<LabOrder?> _order = services.orders.watchOrder(widget.orderId);
  Lab? _lab;

  Future<Lab> _labFor(String labId) async {
    if (_lab?.id == labId) return _lab!;
    for (final l in services.labs.cachedLabs() ?? <Lab>[]) {
      if (l.id == labId) return _lab = l;
    }
    return _lab = await services.labs.fetchLab(labId);
  }

  Future<void> _cancel(LabOrder o) async {
    final t = AppLocalizations.of(context);
    if (!await confirmDialog(context, t.cancelConfirm, confirmLabel: t.cancelBooking, danger: true)) return;
    if (!mounted) return;
    final reason = await promptDialog(context, t.reasonOptional);
    if (reason == null) return;
    try {
      await services.orders.setStatus(o.id, OrderStatus.cancelled, reason: reason.isEmpty ? null : reason);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _messageLab(LabOrder o) async {
    try {
      final lab = await _labFor(o.labId);
      final conv = await services.messages.open(o.labId, o.patientId);
      if (!mounted) return;
      final lang = SessionScope.read(context).lang;
      context.push('/chat/${conv.id}?title=${Uri.encodeComponent(lab.name(lang))}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(),
      body: StreamBuilder<LabOrder?>(
        stream: _order,
        builder: (context, snap) {
          if (snap.hasError && !snap.hasData) {
            return ErrorState(message: friendlyError(context, snap.error!), onRetry: () => setState(() {}));
          }
          final o = snap.data;
          if (o == null) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(child: Text(o.packageName(lang), style: Theme.of(context).textTheme.titleLarge)),
              StatusChip(o.status),
            ]),
            const SizedBox(height: 4),
            FutureBuilder<Lab>(
              future: _labFor(o.labId),
              builder: (_, s) => Text(s.data?.name(lang) ?? ''),
            ),
            Text('${formatDateTime(o.createdAt, lang)} · ${t.priceIqd(formatIqd(o.priceIqd, lang))}',
                style: Theme.of(context).textTheme.bodySmall),
            if (o.statusReason != null && (o.status == OrderStatus.refused || o.status == OrderStatus.cancelled)) ...[
              const SizedBox(height: 8),
              Text(o.statusReason!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            if (o.status == OrderStatus.onWay) ...[
              _LiveTracking(order: o),
              const SizedBox(height: 16),
            ] else if (o.status == OrderStatus.accepted) ...[
              Card(
                child: ListTile(leading: const Icon(Icons.directions_car_outlined), title: Text(t.trackingNotStarted)),
              ),
              const SizedBox(height: 16),
            ],
            SectionTitle(t.timeline),
            _Timeline(order: o),
            SectionTitle(t.results),
            DocumentsList(patientId: o.patientId, orderId: o.id, emptyText: t.noDocuments),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _messageLab(o),
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(t.messageLab),
            ),
            if (o.status == OrderStatus.pending || o.status == OrderStatus.accepted) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _cancel(o),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(t.cancelBooking),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});
  final LabOrder order;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    final c = Theme.of(context).colorScheme;
    return FutureBuilder<List<OrderEvent>>(
      // Re-fetch whenever the status changes.
      key: ValueKey(order.status),
      future: services.orders.fetchEvents(order.id),
      builder: (context, snap) {
        final events = snap.data ?? const <OrderEvent>[];
        final steps = [
          OrderStatus.pending,
          OrderStatus.accepted,
          OrderStatus.onWay,
          OrderStatus.sampleTaken,
          OrderStatus.completed,
        ];
        final closed = order.status == OrderStatus.refused || order.status == OrderStatus.cancelled;
        final shown = closed ? [OrderStatus.pending, order.status] : steps;
        DateTime? at(OrderStatus s) {
          for (final e in events.reversed) {
            if (e.toStatus == s) return e.createdAt;
          }
          return null;
        }

        return Column(children: [
          for (final s in shown)
            Builder(builder: (_) {
              final when = at(s);
              final done = when != null;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: done ? (closed && s != OrderStatus.pending ? c.error : c.primary) : c.outlineVariant),
                title: Text(_label(t, s)),
                trailing: when == null ? null : Text(formatTime(when, lang)),
              );
            }),
        ]);
      },
    );
  }

  String _label(AppLocalizations t, OrderStatus s) => switch (s) {
        OrderStatus.pending => t.statusPending,
        OrderStatus.accepted => t.statusAccepted,
        OrderStatus.refused => t.statusRefused,
        OrderStatus.onWay => t.statusOnWay,
        OrderStatus.sampleTaken => t.statusSampleTaken,
        OrderStatus.completed => t.statusCompleted,
        OrderStatus.cancelled => t.statusCancelled,
      };
}

/// Map with the patient's pin and the runner moving towards it.
class _LiveTracking extends StatefulWidget {
  const _LiveTracking({required this.order});
  final LabOrder order;

  @override
  State<_LiveTracking> createState() => _LiveTrackingState();
}

class _LiveTrackingState extends State<_LiveTracking> {
  late final Stream<RunnerLocation?> _runner = services.orders.watchRunner(widget.order.id);
  late final Future<String?> _runnerName =
      widget.order.runnerId == null ? Future.value(null) : services.orders.personName(widget.order.runnerId!);
  GoogleMapController? _map;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refresh "last updated N min ago" even if no new position arrives.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final home = LatLng(widget.order.lat, widget.order.lng);
    return StreamBuilder<RunnerLocation?>(
      stream: _runner,
      builder: (context, snap) {
        final r = snap.data;
        final runnerPos = r == null ? null : LatLng(r.lat, r.lng);
        if (runnerPos != null && _map != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _map?.animateCamera(CameraUpdate.newLatLngBounds(_bounds(home, runnerPos), 60));
          });
        }
        final minutesAgo = r == null ? null : DateTime.now().difference(r.updatedAt).inMinutes;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 240,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: runnerPos ?? home, zoom: 14),
                onMapCreated: (m) => _map = m,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                markers: {
                  Marker(markerId: const MarkerId('home'), position: home, infoWindow: InfoWindow(title: t.you)),
                  if (runnerPos != null)
                    Marker(
                      markerId: const MarkerId('runner'),
                      position: runnerPos,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                      infoWindow: InfoWindow(title: t.runner),
                    ),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FutureBuilder<String?>(
                future: _runnerName,
                builder: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.runnerOnTheWay(s.data ?? t.runner), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (minutesAgo != null && minutesAgo >= 1)
                    Text(t.lastSeenMinutes(minutesAgo), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  LatLngBounds _bounds(LatLng a, LatLng b) => LatLngBounds(
        southwest: LatLng(a.latitude < b.latitude ? a.latitude : b.latitude,
            a.longitude < b.longitude ? a.longitude : b.longitude),
        northeast: LatLng(a.latitude > b.latitude ? a.latitude : b.latitude,
            a.longitude > b.longitude ? a.longitude : b.longitude),
      );
}
