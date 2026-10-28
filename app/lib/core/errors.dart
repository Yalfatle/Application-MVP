import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';

/// True for errors caused by a missing or flaky connection.
bool isNetworkError(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection closed') ||
      s.contains('Connection reset') ||
      s.contains('XMLHttpRequest') ||
      s.contains('Network is unreachable');
}

/// Turns any error into a short, human message in the user's language.
String friendlyError(BuildContext context, Object e) {
  final t = AppLocalizations.of(context);
  if (isNetworkError(e)) return t.errorNetwork;
  if (e is PostgrestException) {
    if (e.code == '42501' || e.message.contains('not allowed') || e.message.contains('permission')) {
      return t.notAllowed;
    }
  }
  if (e is StorageException && (e.statusCode == '403' || e.statusCode == '401')) {
    return t.notAllowed;
  }
  return t.errorGeneric;
}

void showError(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(friendlyError(context, e)), behavior: SnackBarBehavior.floating),
  );
}

void showMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
