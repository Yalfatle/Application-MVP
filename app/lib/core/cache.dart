import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny JSON cache on the device. Screens show cached data instantly and
/// refresh in the background, so the app opens fast on a weak connection
/// and still works offline.
class LocalCache {
  LocalCache(this._prefs);
  final SharedPreferences _prefs;

  static const _prefix = 'cache:';

  static Future<LocalCache> open() async => LocalCache(await SharedPreferences.getInstance());

  T? read<T>(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded['v'] as T?;
    } catch (_) {
      return null;
    }
  }

  DateTime? savedAt(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final ms = (jsonDecode(raw) as Map<String, dynamic>)['t'] as int?;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Object? value) => _prefs.setString(
        '$_prefix$key',
        jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'v': value}),
      );

  Future<void> remove(String key) => _prefs.remove('$_prefix$key');

  /// Wipes everything cached for the signed-in user (on sign out).
  Future<void> clearUserData() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('${_prefix}user:'))) {
      await _prefs.remove(k);
    }
  }

  // Plain settings (not cache).
  String? getSetting(String key) => _prefs.getString('setting:$key');
  Future<void> setSetting(String key, String value) => _prefs.setString('setting:$key', value);
}
