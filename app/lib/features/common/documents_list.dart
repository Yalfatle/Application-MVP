import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/session.dart';
import '../../data/documents_repository.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import 'widgets.dart';

/// A patient's documents. Patients can open them; lab staff can also
/// upload new ones and delete them.
class DocumentsList extends StatefulWidget {
  const DocumentsList({
    super.key,
    required this.patientId,
    this.orderId,
    this.uploadLabId,
    this.canDelete = false,
    required this.emptyText,
  });

  final String patientId;

  /// Only show documents for this booking.
  final String? orderId;

  /// Set for staff: uploads go into this lab's folder.
  final String? uploadLabId;
  final bool canDelete;
  final String emptyText;

  @override
  State<DocumentsList> createState() => DocumentsListState();
}

class DocumentsListState extends State<DocumentsList> {
  late Future<List<PatientDocument>> _docs = _load();
  bool _uploading = false;

  Future<List<PatientDocument>> _load() async {
    final all = await services.documents.forPatient(widget.patientId);
    return widget.orderId == null ? all : all.where((d) => d.orderId == widget.orderId).toList();
  }

  void refresh() => setState(() => _docs = _load());

  Future<void> _open(PatientDocument d) async {
    try {
      final url = await services.documents.openLink(d);
      if (mounted) await openExternal(context, url);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(PatientDocument d) async {
    final t = AppLocalizations.of(context);
    if (!await confirmDialog(context, t.deleteDocumentConfirm, confirmLabel: t.delete, danger: true)) return;
    try {
      await services.documents.delete(d.id);
      refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Staff: pick a file and upload it. Lab connections can be slow, so
  /// there's no time pressure; the button just shows progress.
  Future<bool> upload() async {
    final t = AppLocalizations.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true, // works on web and mobile alike
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null || !mounted) return false;
    if (file.size > DocumentsRepository.maxBytes) {
      showMessage(context, t.fileTooLarge);
      return false;
    }
    final title = await promptDialog(context, t.documentTitle, initial: file.name.split('.').first);
    if (title == null) return false;
    setState(() => _uploading = true);
    try {
      await services.documents.upload(
        labId: widget.uploadLabId!,
        patientId: widget.patientId,
        orderId: widget.orderId,
        bytes: file.bytes!,
        fileName: file.name,
        title: title,
      );
      if (mounted) showMessage(context, t.uploaded);
      refresh();
      return true;
    } catch (e) {
      if (mounted) showError(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lang = SessionScope.of(context).lang;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FutureBuilder<List<PatientDocument>>(
        future: _docs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasError) return ErrorState(message: friendlyError(context, snap.error!), onRetry: refresh);
          final docs = snap.data!;
          if (docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(widget.emptyText, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            );
          }
          return Column(children: [
            for (final d in docs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(d.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                  title: Text(d.displayName),
                  subtitle: Text(formatDateTime(d.createdAt, lang)),
                  onTap: () => _open(d),
                  trailing: widget.canDelete
                      ? IconButton(icon: const Icon(Icons.delete_outline), tooltip: t.delete, onPressed: () => _delete(d))
                      : const Icon(Icons.open_in_new),
                ),
              ),
          ]);
        },
      ),
      if (widget.uploadLabId != null)
        OutlinedButton.icon(
          onPressed: _uploading ? null : upload,
          icon: _uploading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(t.uploadResult),
        ),
    ]);
  }
}
