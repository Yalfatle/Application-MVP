import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../common/widgets.dart';

/// One conversation between a lab and a patient. Used by both sides.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.conversationId, required this.title});
  final String conversationId;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ChatView(conversationId: conversationId),
      );
}

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final Stream<List<ChatMessage>> _messages = services.messages.watch(widget.conversationId);
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    services.messages.markRead(widget.conversationId).ignore();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await services.messages.send(widget.conversationId, text);
      _input.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = SessionScope.of(context);
    final iAmPatient = !session.role.isStaff && session.role != UserRole.superAdmin;
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      Expanded(
        child: StreamBuilder<List<ChatMessage>>(
          stream: _messages,
          builder: (context, snap) {
            if (snap.hasError && !snap.hasData) {
              return ErrorState(message: friendlyError(context, snap.error!), onRetry: () => setState(() {}));
            }
            final msgs = snap.data;
            if (msgs == null) return const Center(child: CircularProgressIndicator());
            if (msgs.isEmpty) return EmptyState(message: t.noMessages, icon: Icons.chat_bubble_outline);
            final ordered = msgs.reversed.toList();
            return ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: ordered.length,
              itemBuilder: (context, i) {
                final m = ordered[i];
                final mine = iAmPatient ? !m.toPatient : m.toPatient;
                return Align(
                  alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: mine ? c.primaryContainer : c.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.body),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (m.viaWhatsApp) ...[
                            Icon(Icons.chat, size: 12, color: c.outline),
                            const SizedBox(width: 4),
                            Text(t.viaWhatsApp, style: TextStyle(fontSize: 11, color: c.outline)),
                            const SizedBox(width: 6),
                          ],
                          Text(formatTime(m.createdAt, session.lang), style: TextStyle(fontSize: 11, color: c.outline)),
                        ]),
                      ]),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(hintText: t.typeMessage, counterText: '', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              tooltip: t.send,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ]),
        ),
      ),
    ]);
  }
}
