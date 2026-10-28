import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/cache.dart';
import 'models.dart';

class LabsRepository {
  LabsRepository(this.cache);
  final LocalCache cache;
  SupabaseClient get _db => Supabase.instance.client;

  // Only the columns screens actually use: smaller responses on slow links.
  static const _labCols =
      'id,name_ar,name_en,description_ar,description_en,area_ar,area_en,address_ar,address_en,'
      'lat,lng,contact_phone,contact_whatsapp,contact_email,cover_photo_path,commission_rate,is_active';
  static const _pkgCols = 'id,lab_id,name_ar,name_en,description_ar,description_en,price_iqd,is_active,position';

  List<Lab>? cachedLabs() =>
      cache.read<List<dynamic>>('labs')?.map((e) => Lab.fromJson(e as Map<String, dynamic>)).toList();

  /// Active labs for patients (or every lab for super admins).
  Future<List<Lab>> fetchLabs({bool includeHidden = false}) async {
    var q = _db.from('labs').select(_labCols);
    if (!includeHidden) q = q.eq('is_active', true);
    final rows = await q.order('name_ar');
    final labs = rows.map(Lab.fromJson).toList();
    if (!includeHidden) await cache.write('labs', labs.map((l) => l.toJson()).toList());
    return labs;
  }

  Future<Lab> fetchLab(String id) async {
    final row = await _db.from('labs').select(_labCols).eq('id', id).single();
    return Lab.fromJson(row);
  }

  List<LabPackage>? cachedPackages(String labId) => cache
      .read<List<dynamic>>('packages:$labId')
      ?.map((e) => LabPackage.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<List<LabPackage>> fetchPackages(String labId, {bool includeHidden = false}) async {
    var q = _db.from('packages').select(_pkgCols).eq('lab_id', labId);
    if (!includeHidden) q = q.eq('is_active', true);
    final rows = await q.order('position').order('name_ar');
    final pkgs = rows.map(LabPackage.fromJson).toList();
    if (!includeHidden) await cache.write('packages:$labId', pkgs.map((p) => p.toJson()).toList());
    return pkgs;
  }

  String photoUrl(String path) => _db.storage.from('lab-photos').getPublicUrl(path);

  Future<List<String>> fetchPhotoPaths(String labId) async {
    final rows = await _db.from('lab_photos').select('storage_path').eq('lab_id', labId).order('position');
    return rows.map((r) => r['storage_path'] as String).toList();
  }

  // ---------------------------------------------------------------- admin

  Future<Lab> createLab({required String nameAr, required String nameEn}) async {
    final row = await _db.from('labs').insert({'name_ar': nameAr, 'name_en': nameEn}).select(_labCols).single();
    return Lab.fromJson(row);
  }

  Future<void> updateLab(String id, Map<String, dynamic> fields) =>
      _db.from('labs').update(fields).eq('id', id);

  Future<void> deleteLab(String id) => _db.from('labs').delete().eq('id', id);

  Future<void> savePackage({
    String? id,
    required String labId,
    required String nameAr,
    required String nameEn,
    required int priceIqd,
    String? descriptionAr,
    String? descriptionEn,
    bool isActive = true,
  }) async {
    final data = {
      'lab_id': labId,
      'name_ar': nameAr,
      'name_en': nameEn,
      'price_iqd': priceIqd,
      'description_ar': descriptionAr,
      'description_en': descriptionEn,
      'is_active': isActive,
    };
    if (id == null) {
      await _db.from('packages').insert(data);
    } else {
      await _db.from('packages').update(data).eq('id', id);
    }
  }

  Future<void> deletePackage(String id) => _db.from('packages').delete().eq('id', id);

  Future<void> addPhoto(String labId, Uint8List bytes, String fileName, String mimeType) async {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final path = '$labId/${const Uuid().v4()}.$ext';
    await _db.storage.from('lab-photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, cacheControl: '604800'),
        );
    await _db.from('lab_photos').insert({'lab_id': labId, 'storage_path': path});
    // First photo becomes the cover.
    final lab = await fetchLab(labId);
    if (lab.coverPhotoPath == null) await updateLab(labId, {'cover_photo_path': path});
  }

  Future<void> deletePhoto(String labId, String path) async {
    await _db.from('lab_photos').delete().eq('storage_path', path);
    await _db.storage.from('lab-photos').remove([path]);
    final lab = await fetchLab(labId);
    if (lab.coverPhotoPath == path) {
      final rest = await fetchPhotoPaths(labId);
      await updateLab(labId, {'cover_photo_path': rest.isEmpty ? null : rest.first});
    }
  }
}
