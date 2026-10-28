import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import 'models.dart';

class CreatedInvite {
  CreatedInvite(this.link, this.expiresAt);
  final String link;
  final DateTime expiresAt;
}

class InvitePreview {
  InvitePreview({required this.labNameAr, required this.labNameEn, required this.role, required this.expiresAt});
  final String labNameAr;
  final String labNameEn;
  final UserRole role;
  final DateTime expiresAt;
}

/// Employees, invites, earnings, and platform-level admin.
class StaffRepository {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<StaffMember>> labStaff(String labId) async {
    final rows = await _db.rpc('lab_staff', params: {'p_lab_id': labId}) as List;
    return rows.map((r) => StaffMember.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<StaffMember>> runners(String labId) async =>
      (await labStaff(labId)).where((s) => s.role == UserRole.runner || s.role == UserRole.labAdmin).toList();

  Future<List<StaffInvite>> invites(String labId) async {
    final rows = await _db
        .from('staff_invites')
        .select('id,role,expires_at,used_at,revoked_at')
        .eq('lab_id', labId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(StaffInvite.fromJson).toList();
  }

  Future<CreatedInvite> createInvite(String labId, UserRole role) async {
    final rows = await _db.rpc('create_staff_invite', params: {'p_lab_id': labId, 'p_role': role.db}) as List;
    final r = rows.first as Map<String, dynamic>;
    final base = Env.adminWebUrl.isNotEmpty ? Env.adminWebUrl : Uri.base.origin;
    final link = '${base.replaceAll(RegExp(r'/$'), '')}/#/join?token=${r['token']}';
    return CreatedInvite(link, DateTime.parse(r['expires_at'] as String).toLocal());
  }

  Future<void> revokeInvite(String id) => _db.rpc('revoke_staff_invite', params: {'p_invite_id': id});

  Future<InvitePreview?> peekInvite(String token) async {
    final rows = await _db.rpc('peek_staff_invite', params: {'p_token': token}) as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return InvitePreview(
      labNameAr: r['lab_name_ar'] as String,
      labNameEn: r['lab_name_en'] as String,
      role: UserRole.parse(r['role'] as String?),
      expiresAt: DateTime.parse(r['expires_at'] as String).toLocal(),
    );
  }

  /// Returns null on success, or an error code from the server.
  Future<String?> redeemInvite({
    required String token,
    required String fullName,
    required String password,
    String? email,
    String? phone,
  }) async {
    try {
      await _db.functions.invoke('redeem-invite', body: {
        'token': token,
        'full_name': fullName,
        'password': password,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
      });
      return null;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] is String) return details['error'] as String;
      return 'server_error';
    }
  }

  Future<void> setRole(String userId, UserRole role) =>
      _db.rpc('set_employee_role', params: {'p_user_id': userId, 'p_role': role.db});

  Future<void> remove(String userId) => _db.rpc('remove_employee', params: {'p_user_id': userId});

  Future<List<EarningsRow>> earnings(DateTime from, DateTime to) async {
    final rows = await _db.rpc('lab_earnings', params: {
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    }) as List;
    return rows.map((r) => EarningsRow.fromJson(r as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------- platform

  Future<double> defaultCommission() async {
    final row = await _db.from('app_settings').select('commission_rate').single();
    return (row['commission_rate'] as num).toDouble();
  }

  Future<void> setDefaultCommission(double rate) =>
      _db.from('app_settings').update({'commission_rate': rate}).eq('id', true);

  Future<List<AdminUserRow>> searchUsers(String query) async {
    final rows = await _db.rpc('admin_list_users', params: {'p_search': query, 'p_limit': 100}) as List;
    return rows.map((r) => AdminUserRow.fromJson(r as Map<String, dynamic>)).toList();
  }
}
