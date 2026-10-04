/// The ADR-011 confidence badge. **Hard rule, enforced by construction, not
/// just convention:** there is no fifth, "all clear" state and no green
/// color anywhere in its color table -- every one of the four bands
/// (`high | moderate | low | stale`) carries its own hedge text, and
/// `docs/DECISIONS.md` ADR-011 is explicit that a future UI change adding a
/// green "clear" badge must be treated as a defect, not a style choice.
library;

import 'package:flutter/material.dart';
import 'package:pulse_router/pulse_router.dart';

/// Renders [band] as a colored, hedge-texted badge. Never renders a
/// single-color "all clear" state for any band (ADR-011).
class ConfidenceBadge extends StatelessWidget {
  /// Creates a badge for [band].
  const ConfidenceBadge({required this.band, super.key});

  /// The trace's overall `confidence_band`.
  final ConfidenceBand band;

  /// Deliberately no greens, and deliberately not a simple
  /// red-amber-green traffic-light mapping (that would just be
  /// "all clear" wearing a different color set) -- a cool blue for `high`
  /// down to a plum for `stale`, none of which reads as a safety signal on
  /// its own without the label and hedge text next to it.
  static const Map<ConfidenceBand, Color> _colors = {
    ConfidenceBand.high: Color(0xFF2F6690),
    ConfidenceBand.moderate: Color(0xFFB08900),
    ConfidenceBand.low: Color(0xFFC1440E),
    ConfidenceBand.stale: Color(0xFF6B2E5F),
  };

  static const Map<ConfidenceBand, String> _labels = {
    ConfidenceBand.high: 'High confidence',
    ConfidenceBand.moderate: 'Moderate confidence',
    ConfidenceBand.low: 'Low confidence',
    ConfidenceBand.stale: 'Stale confidence',
  };

  /// Every hedge names the limitation explicitly -- none of these may ever
  /// be replaced with a bare "OK" / "clear" / "safe" string.
  static const Map<ConfidenceBand, String> _hedges = {
    ConfidenceBand.high: 'Plenty of recent hazard data for this route.',
    ConfidenceBand.moderate:
        'Some recent hazard data; parts of the route have less.',
    ConfidenceBand.low:
        'Limited recent hazard data for this route. Not a guarantee about '
        'road conditions.',
    ConfidenceBand.stale:
        'The hazard data for this route is out of date. Not a guarantee '
        'about current conditions.',
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[band]!;
    return Container(
      key: Key('confidence-badge-${band.wireValue}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _labels[band]!,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_hedges[band]!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
