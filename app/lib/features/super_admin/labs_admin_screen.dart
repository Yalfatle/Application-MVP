import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Every lab on the platform: add, hide/show, delete, or open to manage.
class LabsAdminScreen extends StatefulWidget {
  const LabsAdminScreen({super.key});
  @override
  State<LabsAdminScreen> createState() => _LabsAdminScreenState();
}

class _LabsAdminScreenState extends State<LabsAdminScreen> {
  final _view = GlobalKey<LoadViewState<List<Lab>>>();

  Future<void> _add() async {
    final t = AppLocalizations.of(context);
    final ar = TextEditingController();
    final en = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.addLab),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ar, decoration: InputDecoration(labelText: t.nameAr)),
          const SizedBox(height: 10),
          TextField(controller: en, decoration: InputDecoration(labelText: t.nameEn)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.add)),
        ],
      ),
    );
    final nameAr = ar.text.trim();
    final nameEn = en.text.trim();
    ar.dispose();
    en.dispose();
    if (ok != true || nameAr.isEmpty || nameEn.isEmpty) return;
    try {
      final lab = await services.labs.createLab(nameAr: nameAr, nameEn: nameEn);
      if (mounted) context.push('/super/lab/${lab.id}');
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggle(Lab l) async {
    try {
      await services.labs.updateLab(l.id, {'is_active': !l.isActive});
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Lab l) async {
    final t = AppLocalizations.of(context);
    if (!await confirmDialog(context, t.deleteLabConfirm, danger: true, confirmLabel: t.deleteLab)) return;
    try {
      await services.labs.deleteLab(l.id);
      _view.currentState?.reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(t.addLab),
      ),
      body: LoadView<List<Lab>>(
        key: _view,
        load: () => services.labs.fetchLabs(includeHidden: true),
        isEmpty: (l) => l.isEmpty,
        builder: (context, labs, _) => ContentWidth(
          maxWidth: 1000,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: labs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final l = labs[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(l.isActive ? Icons.local_hospital : Icons.visibility_off)),
                  title: Text(l.name(lang)),
                  subtitle: Text([l.area(lang), if (!l.isActive) t.hidden].whereType<String>().join(' · ')),
                  onTap: () => context.push('/super/lab/${l.id}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) => switch (a) {
                      'toggle' => _toggle(l),
                      'delete' => _delete(l),
                      _ => context.push('/super/lab/${l.id}'),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'manage', child: Text(t.manage)),
                      PopupMenuItem(value: 'toggle', child: Text(l.isActive ? t.hideLab : t.showLab)),
                      PopupMenuItem(value: 'delete', child: Text(t.deleteLab)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
