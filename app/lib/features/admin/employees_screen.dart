import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../data/staff_repository.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/widgets.dart';

/// The lab's team, plus invite links for new runners and clerks.
/// Platform admins can also invite the lab owner from here.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.labId});
  final String labId;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _view = GlobalKey<LoadViewState<(List<StaffMember>, List<StaffInvite>)>>();

  Future<(List<StaffMember>, List<StaffInvite>)> _load() async {
    final r = await Future.wait([services.staff.labStaff(widget.labId), services.staff.invites(widget.labId)]);
    return (r[0] as List<StaffMember>, (r[1] as List<StaffInvite>).where((i) => i.isOpen).toList());
  }

  void _reload() => _view.currentState?.reload();

  Future<void> _invite(UserRole role) async {
    try {
      final inv = await services.staff.createInvite(widget.labId, role);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => _InviteDialog(invite: inv));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _memberMenu(StaffMember m, String action) async {
    final t = AppLocalizations.of(context);
    try {
      switch (action) {
        case 'clerk':
          await services.staff.setRole(m.id, UserRole.clerk);
        case 'runner':
          await services.staff.setRole(m.id, UserRole.runner);
        case 'remove':
          if (!await confirmDialog(context, t.removeConfirm(m.fullName ?? ''), danger: true, confirmLabel: t.removeFromLab)) {
            return;
          }
          await services.staff.remove(m.id);
      }
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final isSuper = session.role == UserRole.superAdmin;
    return LoadView<(List<StaffMember>, List<StaffInvite>)>(
      key: _view,
      load: _load,
      builder: (context, data, _) {
        final (members, invites) = data;
        return ContentWidth(
          maxWidth: 900,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: () => _invite(UserRole.runner), icon: const Icon(Icons.directions_car), label: Text(t.inviteRunner)),
              FilledButton.tonalIcon(onPressed: () => _invite(UserRole.clerk), icon: const Icon(Icons.badge_outlined), label: Text(t.inviteClerk)),
              if (isSuper)
                OutlinedButton.icon(onPressed: () => _invite(UserRole.labAdmin), icon: const Icon(Icons.storefront), label: Text(t.inviteOwner)),
            ]),
            SectionTitle(t.employees),
            for (final m in members)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(switch (m.role) {
                      UserRole.runner => Icons.directions_car,
                      UserRole.labAdmin => Icons.storefront,
                      _ => Icons.badge_outlined,
                    }),
                  ),
                  title: Text(m.fullName ?? '—'),
                  subtitle: Text(roleLabel(t, m.role)),
                  trailing: m.id == session.userId || (m.role == UserRole.labAdmin && !isSuper)
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (a) => _memberMenu(m, a),
                          itemBuilder: (_) => [
                            if (m.role != UserRole.clerk) PopupMenuItem(value: 'clerk', child: Text(t.makeClerk)),
                            if (m.role != UserRole.runner) PopupMenuItem(value: 'runner', child: Text(t.makeRunner)),
                            PopupMenuItem(value: 'remove', child: Text(t.removeFromLab)),
                          ],
                        ),
                ),
              ),
            if (invites.isNotEmpty) ...[
              SectionTitle(t.openInvites),
              for (final i in invites)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(roleLabel(t, i.role)),
                    subtitle: Text(t.expiresInMinutes(i.expiresAt.difference(DateTime.now()).inMinutes.clamp(0, 60))),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await services.staff.revokeInvite(i.id);
                          _reload();
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                      child: Text(t.revoke),
                    ),
                  ),
                ),
            ],
          ]),
        );
      },
    );
  }
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.invite});
  final CreatedInvite invite;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.inviteLink),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.inviteLinkBody),
          const SizedBox(height: 12),
          SelectableText(invite.link, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace')),
        ]),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.chat),
          label: Text(t.sendOnWhatsApp),
          onPressed: () => openExternal(context, 'https://wa.me/?text=${Uri.encodeComponent(invite.link)}'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(t.copyLink),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invite.link));
            if (context.mounted) showMessage(context, t.copied);
          },
        ),
      ],
    );
  }
}
