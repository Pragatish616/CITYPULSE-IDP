/// "Report water on the road": three taps, no typing (PLAN.md §6.1).
library;

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/features/report/report_repository.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_router/pulse_router.dart';

/// Opens the report sheet for [point].
Future<void> showReportSheet(BuildContext context, GeoPoint point) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReportSheet(point: point),
    );

/// The report form.
class ReportSheet extends ConsumerStatefulWidget {
  /// Creates the form for a report at [point].
  const ReportSheet({required this.point, super.key});

  /// Where the traveller is reporting.
  final GeoPoint point;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportKind _kind = ReportKind.flooded;
  DepthBand _depth = DepthBand.unknown;
  var _busy = false;

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final status = await ref
        .read(reportRepositoryProvider)
        .submit(ReportDraft(kind: _kind, depth: _depth, point: widget.point));
    if (!mounted) return;
    final message = switch (status) {
      SubmitStatus.sent => s(Msg.reportSent),
      SubmitStatus.queued => s(Msg.reportQueued),
      SubmitStatus.rejected => s(Msg.reportFailed),
    };
    if (status == SubmitStatus.rejected) {
      setState(() => _busy = false);
    } else {
      navigator.pop();
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final theme = Theme.of(context);
    final showDepth = _kind != ReportKind.cleared;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s(Msg.reportTitle), style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${s(Msg.reportLocation)}: '
                '${widget.point.lat.toStringAsFixed(4)}, '
                '${widget.point.lon.toStringAsFixed(4)}',
                key: const Key('report-location'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text(s(Msg.reportWhat), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (kind, label) in [
                    (ReportKind.flooded, s(Msg.reportFlooded)),
                    (ReportKind.standing, s(Msg.reportStanding)),
                    (ReportKind.cleared, s(Msg.reportCleared)),
                  ])
                    ChoiceChip(
                      key: Key('kind-${kind.name}'),
                      label: Text(label),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              if (showDepth) ...[
                const SizedBox(height: 16),
                Text(s(Msg.reportDepth), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (band, label) in [
                      (DepthBand.unknown, s(Msg.depthUnknown)),
                      (DepthBand.ankle, s(Msg.depthAnkle)),
                      (DepthBand.knee, s(Msg.depthKnee)),
                      (DepthBand.above, s(Msg.depthAbove)),
                    ])
                      ChoiceChip(
                        key: Key('depth-${band.name}'),
                        label: Text(label),
                        selected: _depth == band,
                        onSelected: (_) => setState(() => _depth = band),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                s(Msg.reportPrivacy),
                key: const Key('report-privacy'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('report-submit'),
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(s(Msg.reportSubmit)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
