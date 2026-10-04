/// The result of a plan: time, the explanation, the confidence badge and the
/// data gaps. Everything the traveller reads about a route is rendered from the
/// `DecisionTrace` through `pulse_explain` (ADR-004), never composed here.
library;

import 'package:citypulse_app/src/core/settings.dart';
import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/providers.dart';
import 'package:citypulse_app/src/ui/widgets/data_gaps_panel.dart';
import 'package:citypulse_app/src/core/city.dart';
import 'package:citypulse_app/src/ui/widgets/advice_card.dart';
import 'package:citypulse_app/src/ui/widgets/explanation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:yaml/yaml.dart';

/// `display_noun` per hazard class, from the bundled `hazard_classes.yaml`
/// (the vocabulary lives in one place, `docs/CONTRACTS.md` §5).
final hazardNounsProvider = FutureProvider<Map<String, String>>((ref) async {
  final yaml = await ref
      .watch(assetBundleProvider)
      .loadString('assets/config/hazard_classes.yaml');
  return EngineConfig.fromMap(loadYaml(yaml) as YamlMap).displayNouns;
});

/// Shows [view].
class RouteCard extends ConsumerWidget {
  /// Creates the card.
  const RouteCard({
    required this.view,
    required this.showFastest,
    required this.onToggleFastest,
    super.key,
  });

  /// The route to describe.
  final RouteView view;

  /// Whether the fastest route is drawn.
  final bool showFastest;

  /// Toggles the fastest-route line.
  final VoidCallback onToggleFastest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final nouns =
        ref.watch(hazardNounsProvider).value ?? const <String, String>{};
    final trace = view.trace;
    // Per route when the server says (Chennai inside Tamil Nadu, ADR-022), else the city's setting.
    final hasHazardLayer =
        view.hazardLayer ?? ref.watch(cityProvider).hazardLayer;

    // Never throws: a Tier 0 failure becomes a fixed sentence (F-07, ADR-016).
    final explanation = renderTemplateSafe(
      trace: trace,
      hazardDisplayNouns: nouns,
      onFailure: (_) {},
    );
    final extra = view.extraMinutes.round();
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(
              _travelIcon(ref.watch(settingsProvider.select((x) => x.travel))),
            ),
            const SizedBox(width: 6),
            Text(
              s.minutes(view.travelMinutes.round()),
              key: const Key('route-minutes'),
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Text(
              s.kilometres(trace.chosen.distanceMeters),
              key: const Key('route-distance'),
              style: text.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          view.detours && extra >= 1
              ? s.withNumber(Msg.longerThanFastest, extra)
              : s(Msg.sameAsFastest),
          key: const Key('route-extra'),
          style: text.bodyMedium,
        ),
        if (view.detours)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('toggle-fastest'),
              onPressed: onToggleFastest,
              icon: Icon(showFastest ? Icons.visibility_off : Icons.visibility),
              label: Text(
                showFastest ? s(Msg.hideFastest) : s(Msg.showFastest),
              ),
            ),
          ),
        // Say so when the route starts or ends away from where the traveller pointed: with a map of
        // main roads only, that can be many kilometres, and a quiet detour would mislead.
        if (view.originSnapMetres >= _farFromRoadMetres)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              s.withKm(Msg.startFarFromRoad, view.originSnapMetres),
              key: const Key('start-far'),
              style: text.bodySmall,
            ),
          ),
        if (view.destinationSnapMetres >= _farFromRoadMetres)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              s.withKm(Msg.endFarFromRoad, view.destinationSnapMetres),
              key: const Key('end-far'),
              style: text.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        // A region with no flood-hazard layer has no hazard confidence to show; a "low confidence"
        // badge and a hazard explanation there would suggest flood data was consulted (ADR-020).
        if (!hasHazardLayer)
          Container(
            key: const Key('no-hazard-note'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(s(Msg.hazardMapNote), style: text.bodyMedium),
          )
        else ...[
          // The advisor (ADR-021) runs on the phone in microseconds, from this route's own trace.
          AdviceCard(
            advice: advise(
              RouteFacts.fromTrace(trace, eventState: view.eventState),
            ),
            strings: s,
          ),
          const SizedBox(height: 12),
          Text(
            s.language == AppLanguage.en
                ? s(Msg.explanationHeading)
                : s(Msg.explanationEnglishOnly),
            style: text.titleSmall,
          ),
          const SizedBox(height: 4),
          ExplanationCard(
            explanation: explanation,
            confidenceBand: trace.confidenceBand,
          ),
          const SizedBox(height: 8),
          DataGapsPanel(dataGaps: trace.dataGaps),
          const SizedBox(height: 8),
        ],
        Text(
          '${s(Msg.settingsComputedOn)} '
          '${view.computedOn == ComputeSite.device ? s(Msg.onDevice) : s(Msg.onServer)}'
          ' · ${view.computeMilliseconds.round()} ms',
          key: const Key('route-computed-on'),
          style: text.bodySmall,
        ),
      ],
    );
  }
}

/// Beyond this distance between the point given and the road used, the card says so.
const double _farFromRoadMetres = 1000;

IconData _travelIcon(TravelType t) => switch (t) {
  TravelType.commuter => Icons.directions_car_outlined,
  TravelType.cyclist => Icons.directions_bike,
  TravelType.pedestrian => Icons.directions_walk,
  TravelType.emergency => Icons.emergency_outlined,
};
