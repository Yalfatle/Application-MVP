import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

class LabMessagesScreen extends StatelessWidget {
  const LabMessagesScreen({super.key, required this.labId});
  final String labId;

  Future<(List<Conversation>, Map<String, String>)> _load() async {
    final convs = await services.messages.forLab(labId);
    final names = await services.orders.patientNames(convs.map((c) => c.patientId));
    return (convs, names);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return LoadView<(List<Conversation>, Map<String, String>)>(
      load: _load,
      isEmpty: (d) => d.$1.isEmpty,
      empty: EmptyState(message: t.noMessages, icon: Icons.chat_bubble_outline),
      builder: (context, data, _) {
        final (convs, names) = data;
        return ContentWidth(
          maxWidth: 900,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: convs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final c = convs[i];
              final name = names[c.patientId] ?? '';
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(name.isEmpty ? '—' : name),
                  subtitle: Text(formatDateTime(c.lastMessageAt, lang)),
                  onTap: () => context.push('/chat/${c.id}?title=${Uri.encodeComponent(name)}'),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
