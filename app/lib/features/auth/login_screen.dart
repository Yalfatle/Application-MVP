import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.translate),
              label: Text(session.lang == 'ar' ? t.english : t.arabic),
              onPressed: () => session.setLocale(session.lang == 'ar' ? 'en' : 'ar'),
            ),
          ],
        ),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 460,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 8),
                Icon(Icons.biotech_rounded, size: 72, color: scheme.primary),
                const SizedBox(height: 12),
                Text(t.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        )),
                const SizedBox(height: 4),
                Text(t.loginWelcome, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TabBar(tabs: [
                  Tab(icon: const Icon(Icons.person_outline), text: t.patientTab),
                  Tab(icon: const Icon(Icons.badge_outlined), text: t.staffTab),
                ]),
                const SizedBox(height: 24),
                const SizedBox(
                  height: 360,
                  child: TabBarView(children: [_PatientLogin(), _StaffLogin()]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Patients sign in with a code sent to WhatsApp. No password to forget.
class _PatientLogin extends StatefulWidget {
  const _PatientLogin();
  @override
  State<_PatientLogin> createState() => _PatientLoginState();
}

class _PatientLoginState extends State<_PatientLogin> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _resendIn = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    final t = AppLocalizations.of(context);
    final phone = normalizeIraqiMobile(_phone.text);
    if (phone == null) {
      setState(() => _error = t.invalidPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithOtp(phone: phone, data: {'locale': SessionScope.read(context).lang});
      if (!mounted) return;
      setState(() => _sentTo = phone);
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final t = AppLocalizations.of(context);
    final code = latinDigits(_code.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (code.length != 6) {
      setState(() => _error = t.invalidCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyOTP(type: OtpType.sms, token: code, phone: _sentTo!);
      // The router moves on automatically once the session updates.
    } on AuthException {
      if (mounted) setState(() => _error = t.invalidCode);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sent = _sentTo != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!sent) ...[
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            labelText: t.phoneLabel,
            hintText: t.phoneHint,
            prefixIcon: const Icon(Icons.phone_iphone),
          ),
          onSubmitted: (_) => _sendCode(),
        ),
      ] else ...[
        Text(t.codeSentTo(_sentTo!), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLength: 6,
          autofocus: true,
          autofillHints: const [AutofillHints.oneTimeCode],
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: InputDecoration(labelText: t.codeLabel, counterText: ''),
          onSubmitted: (_) => _verify(),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _busy ? null : (sent ? _verify : _sendCode),
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(sent ? Icons.check : Icons.chat),
        label: Text(sent ? t.verify : t.sendCode),
      ),
      if (sent) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(
            onPressed: () => setState(() {
              _sentTo = null;
              _code.clear();
              _error = null;
            }),
            child: Text(t.changeNumber),
          ),
          TextButton(
            onPressed: _resendIn > 0 || _busy ? null : _sendCode,
            child: Text(_resendIn > 0 ? t.resendIn(_resendIn) : t.resendCode),
          ),
        ]),
      ],
    ]);
  }
}

/// Lab staff and admins sign in with email or phone + password.
class _StaffLogin extends StatefulWidget {
  const _StaffLogin();
  @override
  State<_StaffLogin> createState() => _StaffLoginState();
}

class _StaffLoginState extends State<_StaffLogin> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final t = AppLocalizations.of(context);
    final id = _id.text.trim();
    if (id.isEmpty || _password.text.isEmpty) {
      setState(() => _error = t.wrongCredentials);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (id.contains('@')) {
        await auth.signInWithPassword(email: id.toLowerCase(), password: _password.text);
      } else {
        final phone = normalizeInternationalPhone(id);
        if (phone == null) throw AuthException('bad phone');
        await auth.signInWithPassword(phone: phone, password: _password.text);
      }
    } on AuthException {
      if (mounted) setState(() => _error = t.wrongCredentials);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _id,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(labelText: t.emailOrPhone, prefixIcon: const Icon(Icons.alternate_email)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: t.password,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _signIn(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.signIn),
        ),
      ]),
    );
  }
}
