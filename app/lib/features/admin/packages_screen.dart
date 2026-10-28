import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Tests the lab offers and their prices.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key, required this.labId});
  final String labId;

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  final _view = GlobalKey<LoadViewState<List<LabPackage>>>();

  Future<void> _edit([LabPackage? p]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PackageDialog(labId: widget.labId, package: p),
    );
    if (saved == true) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(t.addPackage),
      ),
      body: LoadView<List<LabPackage>>(
        key: _view,
        load: () => services.labs.fetchPackages(widget.labId, includeHidden: true),
        isEmpty: (p) => p.isEmpty,
        builder: (context, pkgs, _) => ContentWidth(
          maxWidth: 900,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: pkgs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = pkgs[i];
              return Card(
                child: ListTile(
                  title: Text(p.name(lang)),
                  subtitle: Text(t.priceIqd(formatIqd(p.priceIqd, lang))),
                  leading: Icon(p.isActive ? Icons.visibility : Icons.visibility_off,
                      color: p.isActive ? null : Theme.of(context).colorScheme.outline),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _edit(p),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PackageDialog extends StatefulWidget {
  const _PackageDialog({required this.labId, this.package});
  final String labId;
  final LabPackage? package;

  @override
  State<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends State<_PackageDialog> {
  final _form = GlobalKey<FormState>();
  late final _nameAr = TextEditingController(text: widget.package?.nameAr);
  late final _nameEn = TextEditingController(text: widget.package?.nameEn);
  late final _descAr = TextEditingController(text: widget.package?.descriptionAr);
  late final _descEn = TextEditingController(text: widget.package?.descriptionEn);
  late final _price = TextEditingController(text: widget.package?.priceIqd.toString());
  late bool _active = widget.package?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_nameAr, _nameEn, _descAr, _descEn, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await services.labs.savePackage(
        id: widget.package?.id,
        labId: widget.labId,
        nameAr: _nameAr.text.trim(),
        nameEn: _nameEn.text.trim(),
        descriptionAr: _descAr.text.trim().isEmpty ? null : _descAr.text.trim(),
        descriptionEn: _descEn.text.trim().isEmpty ? null : _descEn.text.trim(),
        priceIqd: int.parse(latinDigits(_price.text).replaceAll(RegExp(r'[^0-9]'), '')),
        isActive: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    if (!await confirmDialog(context, '${t.delete}?', danger: true, confirmLabel: t.delete)) return;
    try {
      await services.labs.deletePackage(widget.package!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Tests with past bookings can't be deleted; hide them instead.
      if (mounted) setState(() => _active = false);
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String? req(String? v) => (v ?? '').trim().isEmpty ? t.required : null;
    return AlertDialog(
      title: Text(widget.package == null ? t.addPackage : t.edit),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _nameAr, decoration: InputDecoration(labelText: t.nameAr), validator: req),
              const SizedBox(height: 10),
              TextFormField(controller: _nameEn, decoration: InputDecoration(labelText: t.nameEn), validator: req),
              const SizedBox(height: 10),
              TextFormField(controller: _descAr, maxLines: 2, decoration: InputDecoration(labelText: t.descriptionAr)),
              const SizedBox(height: 10),
              TextFormField(controller: _descEn, maxLines: 2, decoration: InputDecoration(labelText: t.descriptionEn)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.priceLabel),
                validator: (v) => int.tryParse(latinDigits(v ?? '').replaceAll(RegExp(r'[^0-9]'), '')) == null
                    ? t.required
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text(t.visibleToPatients),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        if (widget.package != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(t.delete),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _busy ? null : _save, child: Text(t.save)),
      ],
    );
  }
}
