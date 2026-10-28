import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../l10n/app_localizations.dart';
import 'labels.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.showAppBar = true});
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final p = session.profile;
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(t.settings)) : null,
      body: ContentWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(p?.fullName ?? ''),
              subtitle: Text(roleLabel(t, session.role)),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: t.edit,
                onPressed: () async {
                  final name = await promptDialog(context, t.fullName, initial: p?.fullName);
                  if (name != null && name.length >= 2) await session.setName(name);
                },
              ),
            ),
          ),
          SectionTitle(t.language),
          Card(
            child: RadioGroup<String>(
              groupValue: session.lang,
              onChanged: (v) => session.setLocale(v ?? 'ar'),
              child: Column(children: [
                RadioListTile<String>(value: 'ar', title: Text(t.arabic)),
                RadioListTile<String>(value: 'en', title: Text(t.english)),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: session.signOut,
            icon: const Icon(Icons.logout),
            label: Text(t.signOut),
          ),
        ]),
      ),
    );
  }
}
