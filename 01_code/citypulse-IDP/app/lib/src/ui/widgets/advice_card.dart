/// The route advice card (ADR-021): one verdict, one risk bar, at most two short reasons.
///
/// Built to be read in a glance. **ADR-011 rules apply, as for the confidence badge:** no green, no
/// "safe", no percentages (the model's numbers are scores, not measured frequencies), and a hedge line
/// is always shown.
library;

import 'package:citypulse_app/src/core/strings.dart';
import 'package:flutter/material.dart';
import 'package:pulse_router/pulse_router.dart';

/// Shows [advice] in the traveller's language through [strings].
class AdviceCard extends StatelessWidget {
  /// Creates the card.
  const AdviceCard({required this.advice, required this.strings, super.key});

  /// What the advisor decided.
  final Advice advice;

  /// The text source.
  final Strings strings;

  // Deliberately no greens (ADR-011): blue for the mildest verdict, amber, then a deep orange.
  static const Color _lower = Color(0xFF2F6690);
  static const Color _moderate = Color(0xFFB08900);
  static const Color _high = Color(0xFFC1440E);

  Color _actionColour(AdviceAction a) => switch (a) {
    AdviceAction.proceedWithCare => _lower,
    AdviceAction.wait => _moderate,
    AdviceAction.avoid => _high,
  };

  IconData _actionIcon(AdviceAction a) => switch (a) {
    AdviceAction.proceedWithCare => Icons.alt_route,
    AdviceAction.wait => Icons.schedule,
    AdviceAction.avoid => Icons.block,
  };

  String _actionText(AdviceAction a) => strings(switch (a) {
    AdviceAction.proceedWithCare => Msg.adviceProceed,
    AdviceAction.wait => Msg.adviceWait,
    AdviceAction.avoid => Msg.adviceAvoid,
  });

  String _riskText(RiskLevel r) => strings(switch (r) {
    RiskLevel.lower => Msg.riskLower,
    RiskLevel.moderate => Msg.riskModerate,
    RiskLevel.high => Msg.riskHigh,
  });

  String _evidenceText(EvidenceLevel e) => strings(switch (e) {
    EvidenceLevel.strong => Msg.evidenceStrong,
    EvidenceLevel.some => Msg.evidenceSome,
    EvidenceLevel.little => Msg.evidenceLittle,
  });

  String _reasonText(AdviceReason r) => strings(switch (r) {
    AdviceReason.highRiskStreet => Msg.reasonHighRiskStreet,
    AdviceReason.someRiskStreets => Msg.reasonSomeRiskStreets,
    AdviceReason.floodedAlternativesAvoided => Msg.reasonFloodedAlternatives,
    AdviceReason.littleData => Msg.reasonLittleData,
    AdviceReason.staleData => Msg.reasonStaleData,
    AdviceReason.noEvent => Msg.reasonNoEvent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = advice.bestAction;
    final colour = _actionColour(action);
    final reasons = [
      for (final r in advice.reasons) _reasonText(r),
      if (advice.choice.compared > 1 && advice.choice.chosenProbability < 0.65)
        strings(Msg.choiceClose),
    ].take(2).toList();
    final riskText = _riskText(advice.riskLevel);
    final evidenceText = _evidenceText(advice.evidence);

    return Semantics(
      container: true,
      // One sentence for a screen reader instead of nine fragments.
      excludeSemantics: true,
      label: [
        '${_actionText(action)}.',
        '$riskText.',
        '$evidenceText.',
        ...reasons,
        strings(Msg.adviceHedge),
      ].join(' '),
      child: Container(
        key: Key('advice-${action.name}'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colour.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_actionIcon(action), size: 20, color: colour),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _actionText(action),
                    key: const Key('advice-verdict'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _RiskBar(risk: advice.risk, key: const Key('advice-risk-bar')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    riskText,
                    key: const Key('advice-risk'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colour,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _EvidenceDots(level: advice.evidence),
                const SizedBox(width: 6),
                Text(
                  evidenceText,
                  key: const Key('advice-evidence'),
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final r in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: 8),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: colour,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(r, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Text(
              strings(Msg.adviceHedge),
              key: const Key('advice-hedge'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three segments whose widths are the model's scores for lower, moderate and high risk. No numbers.
class _RiskBar extends StatelessWidget {
  const _RiskBar({required this.risk, super.key});

  final Map<RiskLevel, double> risk;

  @override
  Widget build(BuildContext context) {
    const colours = {
      RiskLevel.lower: AdviceCard._lower,
      RiskLevel.moderate: AdviceCard._moderate,
      RiskLevel.high: AdviceCard._high,
    };
    return TweenAnimationBuilder<double>(
      // A new answer animates in again.
      key: ValueKey(risk.values.map((v) => v.toStringAsFixed(2)).join('|')),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return LayoutBuilder(
          builder: (context, box) {
            const gap = 3.0;
            final usable = box.maxWidth - 2 * gap;
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final level in RiskLevel.values) ...[
                      Container(
                        width: ((1 / 3) * (1 - t) + risk[level]! * t) * usable,
                        color: colours[level]!.withValues(
                          alpha: level == _top(risk) ? 1 : 0.35,
                        ),
                      ),
                      if (level != RiskLevel.high) const SizedBox(width: gap),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static RiskLevel _top(Map<RiskLevel, double> r) =>
      r.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// Three dots, filled for the evidence level.
class _EvidenceDots extends StatelessWidget {
  const _EvidenceDots({required this.level});

  final EvidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final filled = switch (level) {
      EvidenceLevel.strong => 3,
      EvidenceLevel.some => 2,
      EvidenceLevel.little => 1,
    };
    final colour = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? colour : Colors.transparent,
                border: Border.all(color: colour, width: 1),
              ),
            ),
          ),
      ],
    );
  }
}
