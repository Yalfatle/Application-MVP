import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/staff_repository.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/widgets.dart';

/// Where an invite link lands. The new employee creates their account here.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.token});
  final String token;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final Future<InvitePreview?> _preview =
      widget.token.isEmpty ? Future.value(null) : services.staff.peekInvite(widget.token);
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim().isEmpty ? null : _email.text.trim();
    final phone = _phone.text.trim().isEmpty ? null : normalizeInternationalPhone(_phone.text);
    if (email == null && phone == null) {
      setState(() => _error = t.emailOrPhoneRequired);
      return;
    }
    final code = await services.staff.redeemInvite(
      token: widget.token,
      fullName: _name.text.trim(),
      password: _password.text,
      email: email,
      phone: phone,
    );
    if (!mounted) return;
    setState(() {
      switch (code) {
        case null:
          _done = true;
        case 'invite_invalid':
          _error = t.inviteInvalid;
        case 'account_exists':
          _error = t.accountExists;
        case 'invalid_email':
          _error = t.invalidEmail;
        case 'invalid_phone':
          _error = t.invalidPhone;
        default:
          _error = t.errorGeneric;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(t.appName)),
      body: FutureBuilder<InvitePreview?>(
        future: _preview,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_done) {
            return EmptyState(
              icon: Icons.check_circle_outline,
              message: t.accountCreated,
              action: FilledButton(onPressed: () => context.go('/login'), child: Text(t.signIn)),
            );
          }
          final invite = snap.data;
          if (invite == null) return EmptyState(icon: Icons.link_off, message: t.inviteInvalid);

          final labName = lang == 'ar' ? invite.labNameAr : invite.labNameEn;
          return ContentWidth(
            maxWidth: 480,
            child: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(24), children: [
                Text(t.joinTitle(labName), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(t.joinAs(roleLabel(t, invite.role))),
                Text(t.inviteValidUntil(formatTime(invite.expiresAt, lang)),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: t.fullName),
                  validator: (v) => (v ?? '').trim().length < 2 ? t.required : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: '${t.email} (${t.optional})'),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return null;
                    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s) ? null : t.invalidEmail;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: '${t.phoneLabel} (${t.optional})', hintText: t.phoneHint),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return null;
                    return normalizeInternationalPhone(s) == null ? t.invalidPhone : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.password, helperText: t.passwordMin),
                  validator: (v) => (v ?? '').length < 8 ? t.passwordMin : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: InputDecoration(labelText: t.confirmPassword),
                  validator: (v) => v != _password.text ? t.passwordsDontMatch : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                BusyButton(label: t.createAccount, onPressed: _submit),
              ]),
            ),
          );
        },
      ),
    );
  }
}
