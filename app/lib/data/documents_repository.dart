import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class DocumentsRepository {
  SupabaseClient get _db => Supabase.instance.client;
  static const _bucket = 'patient-documents';
  static const maxBytes = 20 * 1024 * 1024;

  Future<List<PatientDocument>> forPatient(String patientId) async {
    final rows = await _db
        .from('patient_documents')
        .select('id,patient_id,lab_id,order_id,title,file_name,mime_type,storage_path,created_at')
        .eq('patient_id', patientId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(PatientDocument.fromJson).toList();
  }

  static String? mimeFor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }

  Future<void> upload({
    required String labId,
    required String patientId,
    String? orderId,
    required Uint8List bytes,
    required String fileName,
    String? title,
  }) async {
    final mime = mimeFor(fileName);
    if (mime == null) throw ArgumentError('unsupported file type');
    if (bytes.length > maxBytes) throw ArgumentError('file too large');

    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$labId/$patientId/${const Uuid().v4()}-$safeName';

    await _db.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    try {
      await _db.from('patient_documents').insert({
        'patient_id': patientId,
        'lab_id': labId,
        'order_id': orderId,
        'title': (title ?? '').trim().isEmpty ? null : title!.trim(),
        'file_name': fileName,
        'mime_type': mime,
        'size_bytes': bytes.length,
        'storage_path': path,
      });
    } catch (_) {
      // Don't leave an orphan file behind if the record couldn't be saved.
      try {
        await _db.storage.from(_bucket).remove([path]);
      } catch (_) {}
      rethrow;
    }
  }

  /// Short-lived link (10 minutes). A leaked link stops working quickly.
  Future<String> openLink(PatientDocument doc) =>
      _db.storage.from(_bucket).createSignedUrl(doc.storagePath, 600);

  Future<void> delete(String documentId) =>
      _db.rpc('delete_patient_document', params: {'p_document_id': documentId});
}
