import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/services.dart';
import '../../l10n/app_localizations.dart';

/// While this widget is on screen, the runner's position is sent to the
/// server about every 15 seconds (only if they moved), so the patient can
/// watch them arrive. Each update is a few bytes — fine on weak 3G.
/// It stops by itself when the trip ends (the screen changes).
class RunnerBeacon extends StatefulWidget {
  const RunnerBeacon({super.key, required this.orderId});
  final String orderId;

  @override
  State<RunnerBeacon> createState() => _RunnerBeaconState();
}

class _RunnerBeaconState extends State<RunnerBeacon> {
  static const _interval = Duration(seconds: 15);

  StreamSubscription<Position>? _sub;
  Position? _latest;
  DateTime? _lastSent;
  Timer? _timer;
  bool _denied = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((p) {
      _latest = p;
      if (_lastSent == null) _push();
    });
    // Also resend on a timer so the patient sees "updated just now"
    // even while the runner is stuck in traffic.
    _timer = Timer.periodic(_interval, (_) => _push());
  }

  Future<void> _push() async {
    final p = _latest;
    if (p == null || _sending) return;
    _sending = true;
    try {
      await services.orders.sendRunnerLocation(
        widget.orderId,
        p.latitude,
        p.longitude,
        heading: p.heading,
        accuracy: p.accuracy,
      );
      _lastSent = DateTime.now();
      if (mounted) setState(() {});
    } catch (_) {
      // Weak signal: just try again on the next tick.
    } finally {
      _sending = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = Theme.of(context).colorScheme;
    return Card(
      color: _denied ? c.errorContainer : c.primaryContainer,
      child: ListTile(
        leading: Icon(_denied ? Icons.location_off : Icons.share_location,
            color: _denied ? c.onErrorContainer : c.onPrimaryContainer),
        title: Text(_denied ? t.locationOff : t.tripActive),
        subtitle: _denied ? null : Text(t.keepAppOpen),
      ),
    );
  }
}
