import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/services.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/labels.dart';
import '../common/widgets.dart';

/// Platform admins only: find any account, with contact details.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  Timer? _debounce;
  late Future<List<AdminUserRow>> _rows = services.staff.searchUsers('');

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _rows = services.staff.searchUsers(q.trim()));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ContentWidth(
      maxWidth: 1000,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchUsers),
            onChanged: _search,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AdminUserRow>>(
            future: _rows,
            builder: (context, snap) {
              if (snap.hasError) {
                return ErrorState(
                  message: friendlyError(context, snap.error!),
                  onRetry: () => setState(() => _rows = services.staff.searchUsers('')),
                );
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!;
              if (rows.isEmpty) return EmptyState(message: t.nothingHere);
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final u = rows[i];
                  final contact = [u.phone == null ? null : '+${u.phone}', u.email].whereType<String>().join(' · ');
                  return ListTile(
                    title: Text(u.fullName ?? '—'),
                    subtitle: Text(contact, textDirection: TextDirection.ltr),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(roleLabel(t, u.role)),
                      if (u.labNameEn != null) Text(u.labNameEn!, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
