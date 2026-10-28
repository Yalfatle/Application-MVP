import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// First sign-in only: ask the patient's name so the lab knows who to visit.
class NameScreen extends StatefulWidget {
  const NameScreen({super.key});
  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.yourName)),
      body: ContentWidth(
        maxWidth: 460,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.nameNeeded, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(labelText: t.fullName),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            BusyButton(
              label: t.continueLabel,
              onPressed: _name.text.trim().length < 2
                  ? null
                  : () => SessionScope.read(context).setName(_name.text),
            ),
          ]),
        ),
      ),
    );
  }
}
