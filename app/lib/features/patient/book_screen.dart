import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../data/orders_repository.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Booking: drop a pin where the runner should come. No typing an address.
class BookScreen extends StatelessWidget {
  const BookScreen({super.key, required this.labId, required this.packageId});
  final String labId;
  final String packageId;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.chooseLocation)),
      body: LoadView<(Lab, LabPackage)>(
        cached: () {
          Lab? lab;
          LabPackage? pkg;
          for (final l in services.labs.cachedLabs() ?? <Lab>[]) {
            if (l.id == labId) lab = l;
          }
          for (final p in services.labs.cachedPackages(labId) ?? <LabPackage>[]) {
            if (p.id == packageId) pkg = p;
          }
          return (lab != null && pkg != null) ? (lab, pkg) : null;
        },
        load: () async {
          final lab = await services.labs.fetchLab(labId);
          final pkgs = await services.labs.fetchPackages(labId);
          return (lab, pkgs.firstWhere((p) => p.id == packageId));
        },
        builder: (context, data, _) => _BookingForm(lab: data.$1, package: data.$2),
      ),
    );
  }
}

class _BookingForm extends StatefulWidget {
  const _BookingForm({required this.lab, required this.package});
  final Lab lab;
  final LabPackage package;

  @override
  State<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<_BookingForm> {
  static const _baghdad = LatLng(33.3152, 44.3661);

  GoogleMapController? _map;
  LatLng _pin = _baghdad;
  bool _locating = false;
  bool _locationOff = false;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _note.dispose();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationOff = false;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw StateError('off');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw StateError('denied');
      }
      // A quick rough fix first (instant), then a precise one.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _moveTo(LatLng(last.latitude, last.longitude));
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _moveTo(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      if (mounted) setState(() => _locationOff = true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _moveTo(LatLng p) {
    if (!mounted) return;
    setState(() => _pin = p);
    _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 17));
  }

  Future<void> _confirm() async {
    final t = AppLocalizations.of(context);
    final result = await services.orders.book(
      lab: widget.lab,
      package: widget.package,
      lat: _pin.latitude,
      lng: _pin.longitude,
      note: _note.text,
    );
    if (!mounted) return;
    showMessage(context, result == BookingResult.sent ? t.bookingSent : t.bookingQueued);
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: Stack(alignment: Alignment.center, children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _pin, zoom: 15),
            onMapCreated: (m) => _map = m,
            onCameraMove: (pos) => _pin = pos.target,
            myLocationEnabled: !_locationOff,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // The pin stays in the middle; the map moves under it.
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_on, size: 48, color: c.error),
            ),
          ),
          PositionedDirectional(
            top: 12,
            start: 12,
            end: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Icon(_locationOff ? Icons.location_off : Icons.touch_app, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_locationOff ? t.locationOff : (_locating ? t.findingYou : t.dragPinHint))),
                ]),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 12,
            end: 12,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              onPressed: _locating ? null : _locate,
              tooltip: t.useMyLocation,
              child: _locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
        ]),
      ),
      Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.package.name(lang), style: Theme.of(context).textTheme.titleMedium),
                    Text(widget.lab.name(lang), style: TextStyle(color: c.outline)),
                  ]),
                ),
                Text(t.priceIqd(formatIqd(widget.package.priceIqd, lang)),
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: '${t.locationNote} (${t.optional})',
                  hintText: t.locationNoteHint,
                  counterText: '',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.payments_outlined, size: 16, color: c.outline),
                const SizedBox(width: 6),
                Expanded(child: Text(t.payCash, style: Theme.of(context).textTheme.bodySmall)),
              ]),
              const SizedBox(height: 12),
              BusyButton(label: t.confirmBooking, icon: Icons.check, onPressed: _confirm),
            ]),
          ),
        ),
      ),
    ]);
  }
}
