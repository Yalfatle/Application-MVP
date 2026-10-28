import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Staff ↔ patient messages. Messages to patients also go out on WhatsApp
/// from the platform's number; nobody sees anybody's phone number.
class MessagesRepository {
  SupabaseClient get _db => Supabase.instance.client;

  Future<Conversation> open(String labId, String patientId) async {
    final row = await _db.rpc('open_conversation', params: {'p_lab_id': labId, 'p_patient_id': patientId});
    final map = row is List ? row.first as Map<String, dynamic> : row as Map<String, dynamic>;
    return Conversation.fromJson(map);
  }

  Future<List<Conversation>> forLab(String labId) async {
    final rows = await _db
        .from('conversations')
        .select('id,lab_id,patient_id,last_message_at')
        .eq('lab_id', labId)
        .order('last_message_at', ascending: false)
        .limit(200);
    return rows.map(Conversation.fromJson).toList();
  }

  Future<List<Conversation>> forPatient(String patientId) async {
    final rows = await _db
        .from('conversations')
        .select('id,lab_id,patient_id,last_message_at')
        .eq('patient_id', patientId)
        .order('last_message_at', ascending: false);
    return rows.map(Conversation.fromJson).toList();
  }

  Stream<List<ChatMessage>> watch(String conversationId) => _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at')
      .limit(500)
      .map((rows) => rows.map(ChatMessage.fromJson).toList());

  /// Direction is decided by the server from who is sending.
  Future<void> send(String conversationId, String body) => _db.from('messages').insert({
        'conversation_id': conversationId,
        'direction': 'to_patient',
        'body': body.trim(),
      });

  Future<void> markRead(String conversationId) =>
      _db.rpc('mark_conversation_read', params: {'p_conversation_id': conversationId});
}
