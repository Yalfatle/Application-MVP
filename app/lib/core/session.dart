import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import 'cache.dart';

/// Who is signed in, what they're allowed to do, and which language the
/// app is in. The router listens to this to decide which screens to show.
class Session extends ChangeNotifier {
  Session(this.cache) {
    final saved = cache.getSetting('locale');
    _locale = Locale(saved == 'en' ? 'en' : 'ar');
  }

  final LocalCache cache;
  SupabaseClient get _db => Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;
  Profile? _profile;
  bool _ready = false;
  late Locale _locale;

  Profile? get profile => _profile;
  bool get isReady => _ready;
  bool get isSignedIn => _db.auth.currentUser != null;
  String? get userId => _db.auth.currentUser?.id;
  UserRole get role => _profile?.role ?? UserRole.patient;
  String? get labId => _profile?.labId;
  Locale get locale => _locale;
  String get lang => _locale.languageCode;

  /// A signed-in patient who hasn't told us their name yet.
  bool get needsName => isSignedIn && _profile != null && (_profile!.fullName ?? '').trim().isEmpty;

  Future<void> start() async {
    _authSub = _db.auth.onAuthStateChange.listen((state) async {
      if (state.event == AuthChangeEvent.signedOut) {
        _profile = null;
        notifyListeners();
      } else if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession ||
          state.event == AuthChangeEvent.userUpdated) {
        await refreshProfile();
      }
    });

    if (isSignedIn) {
      // Show the right home screen instantly from cache, then confirm online.
      final cached = cache.read<Map<String, dynamic>>('user:profile');
      if (cached != null && cached['id'] == userId) {
        _profile = Profile.fromJson(cached);
      }
      unawaited(refreshProfile());
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    final uid = userId;
    if (uid == null) return;
    try {
      final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
      if (row != null) {
        _profile = Profile.fromJson(row);
        await cache.write('user:profile', _profile!.toJson());
        // Respect the language the user chose on another device.
        if (_profile!.preferredLocale != lang && cache.getSetting('locale') == null) {
          _locale = Locale(_profile!.preferredLocale);
        }
      }
    } catch (_) {
      // Offline: keep whatever we had cached.
    }
    notifyListeners();
  }

  Future<void> setLocale(String code) async {
    _locale = Locale(code == 'en' ? 'en' : 'ar');
    await cache.setSetting('locale', _locale.languageCode);
    notifyListeners();
    final uid = userId;
    if (uid != null) {
      try {
        await _db.from('profiles').update({'preferred_locale': _locale.languageCode}).eq('id', uid);
      } catch (_) {}
    }
  }

  Future<void> setName(String name) async {
    final uid = userId;
    if (uid == null) return;
    await _db.from('profiles').update({'full_name': name.trim()}).eq('id', uid);
    await refreshProfile();
  }

  Future<void> signOut() async {
    await cache.clearUserData();
    _profile = null;
    await _db.auth.signOut();
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Makes the session reachable anywhere below it in the widget tree.
class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child})
      : super(notifier: session);

  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Read without rebuilding when the session changes.
  static Session read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
