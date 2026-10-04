/// Renders `data_gaps` explicitly as "no data," never as implied safety.
/// `docs/CONTRACTS.md` §3: "`data_gaps` is not optional... A system that
/// silently presents ignorance as safety is the failure mode this project
/// exists to criticise." `docs/CHENNAI_PROTOTYPE_SPEC.md` §6's demo script
/// calls for exactly this: "at least one corridor rendered explicitly as
/// *no data* rather than as safe."
library;

import 'package:flutter/material.dart';
import 'package:pulse_router/pulse_router.dart';

/// Shows [dataGaps] as a collapsed, explicit "no data" list.
class DataGapsPanel extends StatelessWidget {
  /// Creates the panel. Renders nothing if [dataGaps] is empty.
  const DataGapsPanel({required this.dataGaps, super.key});

  /// The trace's `data_gaps[]`.
  final List<DataGap> dataGaps;

  @override
  Widget build(BuildContext context) {
    if (dataGaps.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('data-gaps-panel'),
      child: ExpansionTile(
        leading: const Icon(Icons.help_outline),
        title: Text(
          'No recent hazard data for ${dataGaps.length} '
          '${dataGaps.length == 1 ? "corridor" : "corridors"} on this route',
        ),
        subtitle: const Text(
          'Absence of data is not the same as absence of hazard.',
        ),
        children: [
          for (final gap in dataGaps)
            ListTile(dense: true, title: Text(gap.corridor)),
        ],
      ),
    );
  }
}
