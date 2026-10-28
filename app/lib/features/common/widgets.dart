import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import 'labels.dart';

/// Shows cached data right away, then live data; handles loading, error
/// and empty states the same way everywhere.
class LoadView<T> extends StatefulWidget {
  const LoadView({
    super.key,
    required this.load,
    required this.builder,
    this.cached,
    this.isEmpty,
    this.empty,
  });

  final Future<T> Function() load;
  final T? Function()? cached;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  State<LoadView<T>> createState() => LoadViewState<T>();
}

class LoadViewState<T> extends State<LoadView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _data = widget.cached?.call();
    _stale = _data != null;
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _stale = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = _data;
    if (data == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return ErrorState(message: friendlyError(context, _error ?? 'error'), onRetry: reload);
    }
    final body = (widget.isEmpty?.call(data) ?? false)
        ? RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              const SizedBox(height: 80),
              widget.empty ?? EmptyState(message: t.nothingHere),
            ]),
          )
        : RefreshIndicator(onRefresh: reload, child: widget.builder(context, data, reload));
    return Column(
      children: [
        if (_error != null && _stale) OfflineBanner(onRetry: reload),
        if (_loading && _stale) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: body),
      ],
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = Theme.of(context).colorScheme;
    return Material(
      color: c.tertiaryContainer,
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.cloud_off, size: 18, color: c.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(child: Text(t.offlineBanner, style: TextStyle(color: c.onTertiaryContainer))),
            if (onRetry != null) Icon(Icons.refresh, size: 18, color: c.onTertiaryContainer),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: c.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return EmptyState(
      message: message,
      icon: Icons.wifi_off,
      action: FilledButton.tonal(onPressed: onRetry, child: Text(t.retry)),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.queued = false});
  final OrderStatus status;
  final bool queued;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = Theme.of(context).colorScheme;
    final color = queued ? c.outline : statusColor(status, c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        queued ? t.statusQueued : statusLabel(t, status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Keeps forms and lists readable on wide screens (the admin website).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ]),
      );
}

Future<bool> confirmDialog(BuildContext context, String message, {String? confirmLabel, bool danger = false}) async {
  final t = AppLocalizations.of(context);
  final c = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? t.confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a line of text. Returns null if cancelled, '' if left empty.
Future<String?> promptDialog(BuildContext context, String title, {String? hint, String? initial}) async {
  final t = AppLocalizations.of(context);
  final ctrl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 300,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t.confirm)),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}

Future<void> openExternal(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, AppLocalizations.of(context).errorGeneric);
}

/// Runs an action with a spinner on the button and friendly errors.
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.style = BusyStyle.filled,
    this.color,
  });
  final Future<void> Function()? onPressed;
  final String label;
  final IconData? icon;
  final BusyStyle style;
  final Color? color;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

enum BusyStyle { filled, tonal, outlined }

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = (widget.onPressed == null || _busy) ? null : _run;
    final child = _busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
          ]);
    final colored = widget.color == null
        ? null
        : FilledButton.styleFrom(backgroundColor: widget.color, foregroundColor: Colors.white);
    return switch (widget.style) {
      BusyStyle.filled => FilledButton(style: colored, onPressed: onPressed, child: child),
      BusyStyle.tonal => FilledButton.tonal(onPressed: onPressed, child: child),
      BusyStyle.outlined => OutlinedButton(onPressed: onPressed, child: child),
    };
  }
}
