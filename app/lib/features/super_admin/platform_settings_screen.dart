import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// Platform-wide settings. The default fee applies to every lab that
/// doesn't have its own fee set. Existing orders keep the fee they were
/// booked with.
class PlatformSettingsScreen extends StatelessWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => LoadView<double>(
        load: services.staff.defaultCommission,
        builder: (context, rate, reload) => _Form(rate: rate, onSaved: reload),
      );
}

class _Form extends StatefulWidget {
  const _Form({required this.rate, required this.onSaved});
  final double rate;
  final Future<void> Function() onSaved;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late final _pct = TextEditingController(text: (widget.rate * 100).toStringAsFixed(1));

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ContentWidth(
      maxWidth: 520,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _pct,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: t.defaultFee, suffixText: '%'),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: BusyButton(
            label: t.save,
            icon: Icons.save,
            onPressed: () async {
              final v = double.tryParse(latinDigits(_pct.text.trim()));
              if (v == null || v < 0 || v > 100) {
                showMessage(context, t.required);
                return;
              }
              await services.staff.setDefaultCommission(v / 100);
              if (context.mounted) showMessage(context, t.saved);
              await widget.onSaved();
            },
          ),
        ),
      ]),
    );
  }
}
