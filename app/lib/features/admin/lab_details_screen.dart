import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/documents_repository.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Lab owners edit their lab's public details and photos here.
/// Platform admins also see the fee override and visibility switch.
class LabDetailsScreen extends StatelessWidget {
  const LabDetailsScreen({super.key, required this.labId});
  final String labId;

  @override
  Widget build(BuildContext context) => LoadView<Lab>(
        load: () => services.labs.fetchLab(labId),
        builder: (context, lab, reload) => _LabForm(lab: lab, onSaved: reload),
      );
}

class _LabForm extends StatefulWidget {
  const _LabForm({required this.lab, required this.onSaved});
  final Lab lab;
  final Future<void> Function() onSaved;

  @override
  State<_LabForm> createState() => _LabFormState();
}

class _LabFormState extends State<_LabForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late Future<List<String>> _photos = services.labs.fetchPhotoPaths(widget.lab.id);
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final l = widget.lab;
    _c = {
      'name_ar': TextEditingController(text: l.nameAr),
      'name_en': TextEditingController(text: l.nameEn),
      'description_ar': TextEditingController(text: l.descriptionAr),
      'description_en': TextEditingController(text: l.descriptionEn),
      'area_ar': TextEditingController(text: l.areaAr),
      'area_en': TextEditingController(text: l.areaEn),
      'address_ar': TextEditingController(text: l.addressAr),
      'address_en': TextEditingController(text: l.addressEn),
      'contact_phone': TextEditingController(text: l.contactPhone),
      'contact_whatsapp': TextEditingController(text: l.contactWhatsapp),
      'contact_email': TextEditingController(text: l.contactEmail),
      'lat': TextEditingController(text: l.lat?.toString()),
      'lng': TextEditingController(text: l.lng?.toString()),
      'commission': TextEditingController(
          text: l.commissionRate == null ? '' : (l.commissionRate! * 100).toStringAsFixed(1)),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (!_form.currentState!.validate()) return;
    final isSuper = SessionScope.read(context).role == UserRole.superAdmin;
    final fields = <String, dynamic>{
      for (final k in [
        'name_ar', 'name_en', 'description_ar', 'description_en', 'area_ar', 'area_en',
        'address_ar', 'address_en', 'contact_phone', 'contact_whatsapp', 'contact_email',
      ])
        k: _text(k),
      'lat': double.tryParse(latinDigits(_c['lat']!.text.trim())),
      'lng': double.tryParse(latinDigits(_c['lng']!.text.trim())),
    };
    if (isSuper) {
      final pct = double.tryParse(latinDigits(_c['commission']!.text.trim()));
      fields['commission_rate'] = pct == null ? null : pct / 100;
    }
    await services.labs.updateLab(widget.lab.id, fields);
    if (mounted) showMessage(context, t.saved);
    await widget.onSaved();
  }

  Future<void> _addPhoto() async {
    final t = AppLocalizations.of(context);
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = picked?.files.single;
    if (f == null || f.bytes == null) return;
    if (f.size > 5 * 1024 * 1024) {
      if (mounted) showMessage(context, t.fileTooLarge);
      return;
    }
    setState(() => _uploading = true);
    try {
      await services.labs.addPhoto(widget.lab.id, f.bytes!, f.name, DocumentsRepository.mimeFor(f.name) ?? 'image/jpeg');
      setState(() => _photos = services.labs.fetchPhotoPaths(widget.lab.id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _field(String key, String label, {bool required = false, int lines = 1, TextInputType? type, bool ltr = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[key],
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          keyboardType: type,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label),
          validator: required ? (v) => (v ?? '').trim().isEmpty ? AppLocalizations.of(context).required : null : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isSuper = SessionScope.of(context).role == UserRole.superAdmin;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    Widget pair(Widget a, Widget b) =>
        wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]) : Column(children: [a, b]);

    return ContentWidth(
      maxWidth: 900,
      child: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          pair(_field('name_ar', t.nameAr, required: true), _field('name_en', t.nameEn, required: true)),
          pair(_field('description_ar', t.descriptionAr, lines: 2), _field('description_en', t.descriptionEn, lines: 2)),
          pair(_field('area_ar', t.areaAr), _field('area_en', t.areaEn)),
          pair(_field('address_ar', t.addressAr), _field('address_en', t.addressEn)),
          pair(_field('contact_phone', t.contactPhone, type: TextInputType.phone, ltr: true),
              _field('contact_whatsapp', t.contactWhatsapp, type: TextInputType.phone, ltr: true)),
          _field('contact_email', t.contactEmail, type: TextInputType.emailAddress, ltr: true),
          SectionTitle(t.labLocation),
          pair(_field('lat', t.latitude, type: const TextInputType.numberWithOptions(decimal: true, signed: true), ltr: true),
              _field('lng', t.longitude, type: const TextInputType.numberWithOptions(decimal: true, signed: true), ltr: true)),
          if (isSuper) ...[
            SectionTitle(t.labFee),
            _field('commission', '${t.labFee} — ${t.labFeeHint}', type: const TextInputType.numberWithOptions(decimal: true), ltr: true),
          ],
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerEnd, child: BusyButton(label: t.save, icon: Icons.save, onPressed: _save)),
          SectionTitle(
            t.photos,
            trailing: TextButton.icon(
              onPressed: _uploading ? null : _addPhoto,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(t.addPhoto),
            ),
          ),
          FutureBuilder<List<String>>(
            future: _photos,
            builder: (context, snap) {
              final paths = snap.data ?? const <String>[];
              if (paths.isEmpty) return const SizedBox.shrink();
              return Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in paths)
                  Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(services.labs.photoUrl(p), width: 140, height: 100, fit: BoxFit.cover, cacheWidth: 280),
                    ),
                    PositionedDirectional(
                      top: 2,
                      end: 2,
                      child: IconButton.filledTonal(
                        iconSize: 18,
                        icon: const Icon(Icons.close),
                        onPressed: () async {
                          try {
                            await services.labs.deletePhoto(widget.lab.id, p);
                            setState(() => _photos = services.labs.fetchPhotoPaths(widget.lab.id));
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                        },
                      ),
                    ),
                  ]),
              ]);
            },
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}
