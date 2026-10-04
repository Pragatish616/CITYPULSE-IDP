/// Renders a Tier 0 [Explanation] plus, when required, the ADR-011 repeat
/// disclaimer. `docs/DECISIONS.md` ADR-011: "A shorter form of the same
/// sentence repeats on any card whose `confidence_band` is `low` or
/// `stale`." -- this widget is that card.
library;

import 'package:citypulse_app/src/disclaimer/disclaimer_text.dart';
import 'package:flutter/material.dart';
import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

/// Shows [explanation]'s verified text, and the short repeat disclaimer
/// whenever [confidenceBand] is `low` or `stale`.
class ExplanationCard extends StatelessWidget {
  /// Creates the card.
  const ExplanationCard({
    required this.explanation,
    required this.confidenceBand,
    super.key,
  });

  /// The Tier 0 explanation to show. Never shown unless
  /// `explanation.verification.passed` -- callers must not construct one
  /// from unverified text (`renderTemplate` itself enforces this on its own
  /// output, `docs/CONTRACTS.md` §4 rule 5).
  final Explanation explanation;

  /// Drives whether the repeat disclaimer renders (ADR-011).
  final ConfidenceBand confidenceBand;

  bool get _needsRepeatDisclaimer =>
      confidenceBand == ConfidenceBand.low ||
      confidenceBand == ConfidenceBand.stale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              explanation.text,
              key: const Key('explanation-text'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_needsRepeatDisclaimer) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                kRepeatDisclaimer,
                key: const Key('repeat-disclaimer'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
