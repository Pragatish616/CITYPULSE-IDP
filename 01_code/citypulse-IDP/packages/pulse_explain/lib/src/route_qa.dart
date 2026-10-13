/// D0 of the route question answerer (ADR-035, `data/qa/2026-10-13/PREREGISTRATION_QA.md`): answers a
/// traveller's free-text question about a calculated route, in English or Tamil, with **no language
/// model and no network**.
///
/// Two steps, both deterministic:
/// 1. [classifyQuestion] picks one of 18 [QaIntent]s from fixed cue lists. It is built to fail toward
///    [QaIntent.isSafe]: any question that asks for a safety, dryness, openness or permission-to-travel
///    verdict is answered with what CityPulse cannot confirm and what the data shows (ADR-011).
/// 2. [answerQuestion] fills a fixed English or Tamil template from the route's own [DecisionTrace]
///    (and the advisor's output), then runs the text through [verify]. A text that fails verification
///    is never shown: a fixed fallback is returned instead and `usedFallback` is set.
///
/// **What this file does not do.** It reads nothing but the trace and the event state; it invents no
/// number, place or claim; it never says a road is safe, dry, open or passable. The cue lists and the
/// Tamil wording were written without a native speaker's review and have been measured only on a
/// development set (no accuracy claim until the sealed test set is scored). The verifier's numeral,
/// entity and comparative rules read English; Tamil answers are held to the hedge rule and the Tamil
/// safety stems, and for the rest to the templates being deterministic and tested.
library;

import 'package:pulse_explain/src/explanation.dart';
import 'package:pulse_explain/src/verifier.dart';
import 'package:pulse_router/pulse_router.dart';

/// What a question is about. Frozen in the pre-registration.
enum QaIntent {
  /// Why this route was picked.
  whyRoute,

  /// How long or how far.
  timeDistance,

  /// Other routes, a faster one, why not route B.
  alternatives,

  /// Which streets or places were left out.
  avoidedStreets,

  /// What flood risk is on the route.
  routeHazard,

  /// A safety, dryness, openness or passability verdict, or permission to travel. Always refused.
  isSafe,

  /// Whether to go now, wait or leave.
  shouldGo,

  /// How sure, how old or reliable the data is.
  confidence,

  /// Where data is missing.
  dataGaps,

  /// What changes for another travel mode.
  travelMode,

  /// Whether it is raining or a flood event is declared.
  eventState,

  /// Accidents on the route.
  accidents,

  /// Limits of the travel mode.
  limits,

  /// The best time to leave (not available yet).
  departureTime,

  /// Whether it works offline, whether data is live.
  offline,

  /// How the app calculates.
  howItWorks,

  /// What can be asked.
  help,

  /// Anything the route facts cannot answer.
  outOfScope;

  /// The snake_case name used in the question files and the pre-registration.
  String get wireName => switch (this) {
    QaIntent.whyRoute => 'why_route',
    QaIntent.timeDistance => 'time_distance',
    QaIntent.alternatives => 'alternatives',
    QaIntent.avoidedStreets => 'avoided_streets',
    QaIntent.routeHazard => 'route_hazard',
    QaIntent.isSafe => 'is_safe',
    QaIntent.shouldGo => 'should_go',
    QaIntent.confidence => 'confidence',
    QaIntent.dataGaps => 'data_gaps',
    QaIntent.travelMode => 'travel_mode',
    QaIntent.eventState => 'event_state',
    QaIntent.accidents => 'accidents',
    QaIntent.limits => 'limits',
    QaIntent.departureTime => 'departure_time',
    QaIntent.offline => 'offline',
    QaIntent.howItWorks => 'how_it_works',
    QaIntent.help => 'help',
    QaIntent.outOfScope => 'out_of_scope',
  };

  /// Parses [wireName].
  static QaIntent fromWire(String s) =>
      QaIntent.values.firstWhere((i) => i.wireName == s);
}

/// The classifier's result.
class QaClassification {
  /// Creates a result.
  const QaClassification({
    required this.intent,
    required this.score,
    required this.margin,
    required this.locale,
  });

  /// The chosen intent.
  final QaIntent intent;

  /// Its cue score.
  final double score;

  /// Its lead over the next intent (0 when the question matched nothing).
  final double margin;

  /// `"ta"` if the question contains Tamil script, else `"en"`.
  final String locale;
}

/// A question's answer.
class QaAnswer {
  /// Creates an answer.
  const QaAnswer({
    required this.classification,
    required this.text,
    required this.locale,
    required this.factsUsed,
    required this.verification,
    required this.usedFallback,
    this.rejectedClaims = const [],
  });

  /// How the question was understood.
  final QaClassification classification;

  /// The text to show. Always passed [verify], or is the fixed fallback.
  final String text;

  /// `"en"` or `"ta"`.
  final String locale;

  /// Trace field paths the text drew on.
  final List<String> factsUsed;

  /// The verifier's result for [text].
  final VerificationResult verification;

  /// Whether a template failed verification and the fixed fallback was returned instead.
  final bool usedFallback;

  /// The verifier's claims against the rejected template text when [usedFallback]; empty otherwise. For
  /// logging and tests only: the rejected text itself is never kept or shown.
  final List<String> rejectedClaims;
}

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Tamil script block.
final RegExp _tamilScript = RegExp(r'[஀-௿]');

/// The language of a question: Tamil if any Tamil script appears.
String detectLocale(String question) =>
    _tamilScript.hasMatch(question) ? 'ta' : 'en';

String _normalise(String q) {
  var s = q.toLowerCase().replaceAll(RegExp(r"[’'`]"), '');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return ' $s ';
}

typedef _Cue = (String, double);

// A cue with spaces at its ends matches whole words (the question is padded with spaces); a cue without
// matches anywhere (a stem). Tamil is agglutinative, so Tamil cues are stems. Weights are hand-set.
const Map<QaIntent, List<_Cue>> _cues = {
  QaIntent.isSafe: [
    (' safe ', 2),
    (' safely ', 2),
    (' unsafe ', 2),
    ('passable', 2),
    (' dry ', 2),
    (' clear ', 2),
    (' open ', 2),
    (' closed ', 1),
    (' fine ', 2),
    (' ok ', 1),
    (' okay ', 1),
    ('go through', 2),
    ('drive through', 2),
    (' thru ', 2),
    (' cross ', 2),
    (' crossing ', 2),
    ('get through', 2),
    ('go ahead', 2),
    ('green light', 3),
    ('promise', 3),
    ('guarantee', 3),
    ('nothing will go wrong', 3),
    ('flooded right now', 3),
    ('flooded now', 3),
    ('no flooding', 2),
    ('no flood', 2),
    ('can i go', 2),
    ('can i drive', 2),
    ('can i ride', 2),
    ('can i walk', 2),
    ('can i take', 2),
    ('can i cross', 2),
    ('may i', 2),
    ('will my bike', 2),
    ('will my car', 2),
    ('will my scooter', 2),
    ('no problem', 2),
    ('no issue', 2),
    ('it ok to', 2),
    ('its fine', 2),
    ('is it ok', 2),
    ('is it okay', 2),
    ('worry', 2),
    ('பாதுகாப்', 3),
    ('கடக்க', 3),
    ('திறந்திருக்க', 3),
    ('திறந்து', 2),
    ('காய்ந்', 3),
    ('வறண்', 3),
    ('தெளிவாக', 2),
    ('போகலாமா', 3),
    ('செல்லலாமா', 3),
    ('போக முடியுமா', 3),
    ('செல்ல முடியுமா', 3),
    ('போகக்கூடிய', 3),
    ('பிரச்சனை இல்லை', 3),
    ('பிரச்சனையும் இல்லை', 3),
    ('பிரச்சனை எதுவும் இல்லை', 3),
    ('ஆபத்து இல்லை', 3),
    ('ஆபத்தும் இல்லை', 3),
    ('தண்ணீர் இல்லை', 3),
    ('நீர் இல்லை', 3),
    ('வெள்ளம் இல்லை', 3),
    (' கவலை', 2),
    ('சரியா', 1),
  ],
  QaIntent.whyRoute: [
    (' why ', 2),
    ('explain the route', 3),
    ('reason', 2),
    ('made you pick', 3),
    ('what made you', 3),
    ('why this', 1),
    ('ஏன்', 2),
    ('எதற்காக', 3),
    ('காரணம்', 3),
  ],
  QaIntent.timeDistance: [
    ('how long', 3),
    ('how far', 3),
    ('travel time', 3),
    (' eta ', 3),
    ('how much time', 3),
    ('how many km', 3),
    (' km ', 1.5),
    ('distance', 2),
    ('minutes', 1),
    ('get there', 2),
    ('reach', 2),
    ('arrive', 2),
    ('duration', 2),
    ('when will i', 2),
    ('எவ்வளவு நேரம்', 3),
    ('எவ்வளவு தூரம்', 3),
    ('எவ்ளோ நேரம்', 3),
    ('நிமிடம்', 2),
    ('கிலோமீட்டர்', 3),
    ('தூரம்', 2),
    ('பயண நேரம்', 3),
    ('சென்றடை', 3),
  ],
  QaIntent.alternatives: [
    ('another route', 3),
    ('other route', 3),
    ('other way', 3),
    ('another way', 3),
    ('alternative', 3),
    ('faster way', 3),
    ('quicker', 2),
    ('faster', 1.5),
    ('other option', 3),
    ('why not route', 3),
    ('why not the', 3),
    ('what else could i take', 3),
    ('how much slower', 3),
    ('வேறு வழி', 3),
    ('வேற வழி', 3),
    ('மாற்று', 3),
    ('வேறு பாதை', 3),
    ('இன்னொரு', 2),
    ('வேகமான வழி', 3),
    ('வழி b', 3),
    ('வழி a', 3),
    ('வழக்கமான சாலை', 3),
  ],
  QaIntent.avoidedStreets: [
    ('avoid', 2),
    ('left out', 3),
    ('leave out', 3),
    ('skipped', 3),
    (' skip ', 3),
    ('bypass', 3),
    ('which streets', 1.5),
    ('which roads', 1.5),
    ('which places', 1.5),
    ('which stretch', 2),
    ('தவிர்த்', 3),
    ('விடப்பட்ட', 3),
    ('ஒதுக்க', 3),
    ('எந்த தெரு', 1.5),
    ('எந்த சாலை', 1.5),
    ('எந்த பகுதி விட', 3),
  ],
  QaIntent.routeHazard: [
    ('flood risk', 3),
    ('risk', 1.5),
    ('risky', 2),
    ('hazard', 2),
    ('flooding', 2),
    ('flooded', 1.5),
    ('waterlogging', 2),
    ('danger', 1.5),
    ('how bad', 1),
    ('வெள்ள ஆபத்து', 3),
    ('ஆபத்து', 2),
    ('அபாய', 2),
    ('வெள்ள', 1.5),
    ('தண்ணீர் தேங்க', 3),
    ('தேங்க', 2),
    ('வெள்ளம் உள்ளதா', 3),
    ('ஆபத்தான இடங்கள்', 3),
  ],
  QaIntent.shouldGo: [
    ('should i', 3),
    ('wait', 2),
    ('postpone', 3),
    ('advise', 2),
    ('recommend', 2),
    ('go now', 2),
    ('leave now', 3),
    ('better to', 1),
    ('or later', 1),
    ('கிளம்ப', 3),
    ('காத்திரு', 3),
    ('தள்ளிப்போட', 3),
    ('பரிந்துரை', 3),
    ('இப்போது புறப்ப', 3),
    ('ஒத்திவை', 3),
  ],
  QaIntent.confidence: [
    ('how sure', 3),
    ('sure about', 3),
    ('you sure', 3),
    (' u sure', 3),
    ('reliable', 3),
    ('how old', 3),
    ('trust', 3),
    ('confiden', 3),
    ('recent', 2),
    ('fresh', 2),
    ('evidence', 3),
    ('how accurate', 3),
    ('up to date', 2),
    ('நம்பகம்', 3),
    ('நம்ப', 3),
    ('பழையது', 3),
    ('உறுதியாக', 3),
    ('ஆதாரம்', 3),
    ('புதியதா', 3),
  ],
  QaIntent.dataGaps: [
    ('no data', 3),
    ('missing', 3),
    (' gap', 3),
    ('no reports', 3),
    ('not covered', 3),
    ('know anything', 3),
    ('no info', 3),
    ('without data', 3),
    ('தகவல் இல்லை', 3),
    ('தரவு குறைவு', 3),
    ('காணவில்லை', 3),
    ('இடைவெளி', 3),
    ('அறிக்கை இல்லை', 3),
    ('தெரியாது', 3),
  ],
  QaIntent.travelMode: [
    (' walk', 2),
    ('pedestrian', 3),
    (' bike', 2),
    ('cycle', 2),
    ('ambulance', 3),
    ('two wheeler', 3),
    ('two wheelers', 3),
    (' car ', 1.5),
    ('mode', 2),
    ('what if i', 2),
    ('on foot', 3),
    ('bicycle', 3),
    ('emergency', 2),
    ('நடந்து', 3),
    ('சைக்கிள', 3),
    ('ஆம்புலன்ஸ', 3),
    ('பைக்', 3),
    ('காரில்', 3),
    ('பயண முறை', 3),
    ('இருசக்கர', 3),
    ('பாதசாரி', 3),
  ],
  QaIntent.eventState: [
    ('raining', 3),
    (' rain ', 2),
    ('storm', 3),
    ('weather', 2),
    ('flood alert', 3),
    ('flood event', 3),
    (' alert', 2),
    ('warning', 2),
    ('cyclone', 3),
    ('flood map', 3),
    ('event status', 3),
    ('மழை', 2),
    ('பெய்கிறதா', 3),
    ('புயல்', 3),
    ('எச்சரிக்கை', 3),
    ('வெள்ள நிகழ்வு', 3),
    ('வானிலை', 2),
  ],
  QaIntent.accidents: [
    ('accident', 4),
    ('crash', 4),
    ('collision', 4),
    ('விபத்', 4),
    ('மோதல்', 4),
  ],
  QaIntent.limits: [
    ('limit', 3),
    ('restriction', 3),
    ('restrict', 3),
    ('rules for', 3),
    ('blocked for me', 3),
    ('closed to me', 4),
    ('why cant', 3),
    ('ruled out', 3),
    ('not allowed', 3),
    ('வரம்பு', 4),
    ('தடை', 3),
    ('மூடப்பட்ட', 3),
    ('விலக்க', 3),
    ('விலக்கப்பட்ட', 4),
    ('கட்டுப்பாடு', 3),
    ('வழியாக இல்லை', 3),
  ],
  QaIntent.departureTime: [
    ('best time', 3),
    ('what time should', 3),
    ('what time', 2),
    ('when should i', 3),
    ('when is the best', 3),
    ('earlier or later', 3),
    ('leave earlier', 3),
    ('less congestion', 3),
    ('lighter', 2),
    ('depart', 3),
    ('set off', 3),
    ('congestion', 2),
    ('traffic', 1.5),
    ('when to start', 3),
    ('எப்போது புறப்ப', 5),
    ('எப்போது கிளம்ப', 5),
    ('எப்போது தொடங்க', 4),
    ('எந்த நேரத்தில்', 3),
    ('நேரத்தில் கிளம்ப', 4),
    ('நெரிசல்', 3),
    ('சிறந்த நேரம்', 3),
    ('சிறந்த புறப்ப', 3),
    ('முன்னதாக', 3),
    ('பின்னதாக', 3),
  ],
  QaIntent.offline: [
    ('offline', 4),
    ('without internet', 4),
    ('no signal', 4),
    ('network', 3),
    ('internet', 3),
    ('real time', 3),
    (' live', 2),
    ('on my phone', 3),
    ('from a server', 3),
    ('online', 3),
    ('இணையம்', 4),
    ('ஆஃப்லைன', 4),
    ('நெட்', 3),
    ('நேரலை', 3),
    ('சர்வரி', 3),
    ('சர்வர்', 3),
    ('போனிலேயே', 3),
  ],
  QaIntent.howItWorks: [
    ('how does this work', 4),
    ('how do you', 2),
    ('calculate', 2),
    ('method', 3),
    ('what data do you use', 4),
    ('where does your', 3),
    ('computed', 3),
    ('algorithm', 3),
    ('how the app works', 4),
    ('எப்படி கணக்கிட', 4),
    ('எப்படி முடிவு', 4),
    ('எப்படி வேலை', 4),
    ('எந்த தகவலை பயன்படுத்த', 4),
    ('எந்த தகவலை பயன்படுத்து', 4),
    ('எங்கிருந்து வருகிறது', 4),
  ],
  QaIntent.help: [
    ('what can i ask', 5),
    ('what can you do', 5),
    ('what questions', 4),
    ('examples', 3),
    (' help ', 3),
    ('options', 2),
    ('how do i use', 4),
    ('என்ன கேட்கலாம்', 5),
    ('உதவி', 3),
    ('என்ன செய்வாய்', 4),
    ('என்ன கேள்வி', 4),
    ('உதாரண', 3),
    ('வணக்கம்', 2),
  ],
  QaIntent.outOfScope: [
    ('tomorrow', 3),
    ('next week', 3),
    ('forecast', 3),
    ('joke', 4),
    ('cricket', 4),
    ('petrol', 4),
    ('biryani', 4),
    (' cab ', 4),
    ('capital of', 4),
    ('music', 4),
    ('restaurant', 4),
    ('நாளை', 3),
    ('அடுத்த வாரம்', 3),
    ('நகைச்சுவை', 4),
    ('கிரிக்கெட்', 4),
    ('பெட்ரோல்', 4),
    ('உணவகம்', 4),
    ('பாடல்', 4),
  ],
};

/// Below this score nothing matched well enough and the question is out of scope.
const double _minScore = 1.5;

/// The `isSafe` score at which the question is treated as a request for a safety verdict. Any single
/// strong cue reaches it, so the classifier errs toward the refusal.
const double _safeScore = 2.0;

/// Picks the intent of [question].
QaClassification classifyQuestion(String question) {
  final padded = _normalise(question);
  final locale = detectLocale(question);
  final scores = <QaIntent, double>{};
  for (final entry in _cues.entries) {
    var s = 0.0;
    for (final (cue, weight) in entry.value) {
      if (padded.contains(cue)) s += weight;
    }
    scores[entry.key] = s;
  }
  if ((scores[QaIntent.isSafe] ?? 0) >= _safeScore) {
    return QaClassification(
      intent: QaIntent.isSafe,
      score: scores[QaIntent.isSafe]!,
      margin: scores[QaIntent.isSafe]! - _secondBest(scores, QaIntent.isSafe),
      locale: locale,
    );
  }
  QaIntent best = QaIntent.outOfScope;
  var bestScore = 0.0;
  for (final intent in QaIntent.values) {
    final s = scores[intent] ?? 0;
    if (s > bestScore) {
      best = intent;
      bestScore = s;
    }
  }
  if (bestScore < _minScore) {
    return QaClassification(
      intent: QaIntent.outOfScope,
      score: bestScore,
      margin: 0,
      locale: locale,
    );
  }
  return QaClassification(
    intent: best,
    score: bestScore,
    margin: bestScore - _secondBest(scores, best),
    locale: locale,
  );
}

double _secondBest(Map<QaIntent, double> scores, QaIntent except) {
  var second = 0.0;
  for (final e in scores.entries) {
    if (e.key != except && e.value > second) second = e.value;
  }
  return second;
}

// ---------------------------------------------------------------------------
// Answers
// ---------------------------------------------------------------------------

/// The fixed text returned when a template fails verification. It carries the hedge that rule 4 needs.
const String kQaFallbackEn =
    'I cannot answer that from the route data. Hazard data may be limited, so use your own judgement.';

/// Tamil counterpart of [kQaFallbackEn].
const String kQaFallbackTa =
    'இந்த வழியின் தரவிலிருந்து இதற்குப் பதில் சொல்ல முடியவில்லை. தரவு குறைவு; உங்கள் சொந்த முடிவை பயன்படுத்தவும்.';

/// Answers [question] about the route in [trace]. [eventState] is the state the query ran under (it is
/// not in the trace). [locale] overrides the detected language. Never throws on a bad question: an
/// answer that fails [verify] is replaced by the fixed fallback.
QaAnswer answerQuestion({
  required String question,
  required DecisionTrace trace,
  required EventState eventState,
  required Map<String, String> hazardDisplayNouns,
  String? locale,
}) {
  final cls = classifyQuestion(question);
  final lang = locale ?? cls.locale;
  final ta = lang == 'ta';
  final ctx = _Ctx(trace, eventState, hazardDisplayNouns);
  final facts = <String>[];
  var sentences = _compose(cls.intent, ctx, ta, facts);
  sentences = [
    ...sentences,
    if (trace.confidenceBand == ConfidenceBand.low ||
        trace.confidenceBand == ConfidenceBand.stale)
      ta ? _taHedge : _enHedge,
  ];
  final text = sentences.join(' ');
  final verification = verify(
    text,
    trace,
    hazardDisplayNouns: hazardDisplayNouns,
  );
  if (verification.passed) {
    return QaAnswer(
      classification: cls,
      text: text,
      locale: lang,
      factsUsed: List.unmodifiable(facts),
      verification: verification,
      usedFallback: false,
    );
  }
  final fallback = ta ? kQaFallbackTa : kQaFallbackEn;
  final fbVerification = verify(
    fallback,
    trace,
    hazardDisplayNouns: hazardDisplayNouns,
  );
  return QaAnswer(
    classification: cls,
    text: fallback,
    locale: lang,
    factsUsed: const ['chosen.route_id'],
    verification: VerificationResult(
      numeralsGrounded: fbVerification.numeralsGrounded,
      entitiesGrounded: fbVerification.entitiesGrounded,
      contrastiveValid: fbVerification.contrastiveValid,
      unsupportedClaims: fbVerification.unsupportedClaims,
      fallbackUsed: true,
      latencyMs: fbVerification.latencyMs,
    ),
    usedFallback: true,
    rejectedClaims: List.unmodifiable(verification.unsupportedClaims),
  );
}

const String _enHedge =
    'Hazard data for this route is limited, so use your own judgement.';
const String _taHedge =
    'இந்த வழிக்கு தரவு குறைவு; உங்கள் சொந்த முடிவை பயன்படுத்தவும்.';
const String _enGuide = 'This is a guide from the data held, not a guarantee.';
const String _taGuide =
    'இது கிடைக்கும் தரவின் அடிப்படையிலான வழிகாட்டி; உத்தரவாதம் அல்ல.';

class _Ctx {
  _Ctx(this.trace, this.eventState, this.nouns)
    : advice = advise(RouteFacts.fromTrace(trace, eventState: eventState));

  final DecisionTrace trace;
  final EventState eventState;
  final Map<String, String> nouns;
  final Advice advice;

  String get id => trace.chosen.routeId;
  int get minutes => (trace.chosen.freeFlowDurationSeconds / 60).round();
  int get penaltyMinutes =>
      (trace.chosen.hazardTimePenaltySeconds / 60).round();
  String get km => (trace.chosen.distanceMeters / 1000).toStringAsFixed(1);

  ContextFact? fact(String key) {
    for (final f in trace.contextFacts) {
      if (f.key == key) return f;
    }
    return null;
  }

  String noun(BlockingEdge e) => nouns[e.hazardClass] ?? e.hazardClass;
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

List<String> _compose(QaIntent intent, _Ctx c, bool ta, List<String> facts) {
  return switch (intent) {
    QaIntent.whyRoute => _why(c, ta, facts),
    QaIntent.timeDistance => _timeDistance(c, ta, facts),
    QaIntent.alternatives => _alternatives(c, ta, facts),
    QaIntent.avoidedStreets => _avoided(c, ta, facts),
    QaIntent.routeHazard => _hazard(c, ta, facts),
    QaIntent.isSafe => _isSafe(c, ta, facts),
    QaIntent.shouldGo => _shouldGo(c, ta, facts),
    QaIntent.confidence => _confidence(c, ta, facts),
    QaIntent.dataGaps => _dataGaps(c, ta, facts),
    QaIntent.travelMode => _travelMode(c, ta, facts),
    QaIntent.eventState => _eventState(c, ta, facts),
    QaIntent.accidents => _accidents(c, ta, facts),
    QaIntent.limits => _limits(c, ta, facts),
    QaIntent.departureTime => _departure(c, ta, facts),
    QaIntent.offline => _offline(c, ta, facts),
    QaIntent.howItWorks => _how(c, ta, facts),
    QaIntent.help => _help(c, ta, facts),
    QaIntent.outOfScope => _outOfScope(c, ta, facts),
  };
}

// --- shared pieces ----------------------------------------------------------

String _deltaSentence(_Ctx c, bool ta, List<String> facts) {
  facts
    ..add('chosen.route_id')
    ..add('chosen.free_flow_duration_s');
  final t = c.trace;
  if (t.alternatives.isEmpty) {
    return ta
        ? 'இந்த பயணத்துக்கு வழி ${c.id} மட்டுமே கிடைத்தது.'
        : 'Route ${c.id} is the only route found for this trip.';
  }
  final alt = t.alternatives.first;
  facts
    ..add('alternatives[0].route_id')
    ..add('alternatives[0].duration_s');
  final delta = t.chosen.freeFlowDurationSeconds - alt.durationSeconds;
  final m = (delta.abs() / 60).round();
  if (m == 0) {
    return ta
        ? 'வழி ${c.id} கிட்டத்தட்ட வழி ${alt.routeId} போலவே நேரம் எடுக்கும்.'
        : 'Route ${c.id} takes about the same time as Route ${alt.routeId}.';
  }
  if (ta) {
    return 'வழி ${c.id}, வழி ${alt.routeId} ஐ விட $m நிமிடம் '
        '${delta > 0 ? 'மெதுவானது' : 'வேகமானது'}.';
  }
  return 'Route ${c.id} is ${_plural(m, 'minute')} '
      '${delta > 0 ? 'slower' : 'faster'} than Route ${alt.routeId}.';
}

String _ageEn(double seconds) {
  final m = (seconds / 60).round();
  return m <= 0 ? 'moments ago' : '${_plural(m, 'minute')} ago';
}

String _ageTa(double seconds) {
  final m = (seconds / 60).round();
  return m <= 0 ? 'சற்று முன்' : '$m நிமிடங்களுக்கு முன்';
}

String _hazardNounTa(String cls) => switch (cls) {
  'flood' => 'வெள்ளம்',
  'waterlogging' => 'நீர் தேக்கம்',
  'accident' => 'விபத்து',
  'closure' => 'சாலை மூடல்',
  _ => 'ஆபத்து',
};

List<BlockingEdge> _avoidedEdges(_Ctx c) {
  final seen = <int>{};
  final out = <BlockingEdge>[];
  for (final a in c.trace.alternatives) {
    for (final e in a.blockingEdges) {
      if (seen.add(e.edgeId)) out.add(e);
    }
  }
  return out;
}

String _avoidedOne(_Ctx c, BlockingEdge e, bool ta) {
  if (!e.hasObservation) {
    return ta
        ? '${e.streetName} பகுதி வெள்ள வரைபடத்தில் குறிக்கப்பட்டுள்ளது; அங்கிருந்து அறிக்கை எதுவும் வரவில்லை'
        : 'a stretch of ${e.streetName} that the hazard map marks for ${c.noun(e)}, where no report has been received';
  }
  return ta
      ? '${e.streetName} பகுதியில் ${_hazardNounTa(e.hazardClass)} '
            '${_ageTa(e.newestObservationAgeSeconds)} பதிவானது'
      : 'a stretch of ${e.streetName} where ${c.noun(e)} was reported ${_ageEn(e.newestObservationAgeSeconds)}';
}

String _riskWord(RiskLevel r, bool ta) => switch (r) {
  RiskLevel.lower => ta ? 'குறைவு' : 'lower',
  RiskLevel.moderate => ta ? 'மிதமானது' : 'moderate',
  RiskLevel.high => ta ? 'அதிகம்' : 'high',
};

String _evidenceWord(EvidenceLevel e, bool ta) => switch (e) {
  EvidenceLevel.strong => ta ? 'வலுவானது' : 'strong',
  EvidenceLevel.some => ta ? 'ஓரளவு' : 'partial',
  EvidenceLevel.little => ta ? 'குறைவானது' : 'thin',
};

String _reason(AdviceReason r, bool ta) => switch (r) {
  AdviceReason.highRiskStreet =>
    ta
        ? 'இந்த வழியில் குறைந்தது ஒரு தெருவுக்கு அதிக வெள்ள ஆபத்து மதிப்பீடு உள்ளது.'
        : 'At least one street on this route has a high flood risk rating.',
  AdviceReason.someRiskStreets =>
    ta
        ? 'இந்த வழியில் சில தெருக்களுக்கு வெள்ள ஆபத்து மதிப்பீடு உள்ளது.'
        : 'The data rates some streets on this route as carrying a flood risk.',
  AdviceReason.floodedAlternativesAvoided =>
    ta ? 'அதிக வெள்ள ஆபத்து உள்ள தெருக்கள் வழியான வேகமான வழிகள் விடப்பட்டன.' : 'The faster routes through streets with a high flood risk were left out.',
  AdviceReason.littleData =>
    ta
        ? 'இந்த வழிக்கு சமீபத்திய தரவு குறைவு.'
        : 'Little recent data covers this route.',
  AdviceReason.staleData =>
    ta
        ? 'இந்த வழிக்கான தரவு பழையது; தரவு குறைவு.'
        : 'The data for this route is out of date.',
  AdviceReason.noEvent =>
    ta
        ? 'மழை நிகழ்வு அறிவிக்கப்படவில்லை; எனவே வெள்ள வரைபடம் பயன்படுத்தப்படவில்லை.'
        : 'No rain event has been declared, so the flood map is not applied.',
  AdviceReason.noHazardFound =>
    ta
        ? 'எங்களிடம் உள்ள தரவில் இந்த வழியின் அதிக ஆபத்துள்ள தெருவுக்கும் மிகக் குறைவான வெள்ள ஆபத்தே உள்ளது; இது தரவைப் பற்றியது, சாலையைப் பற்றியது அல்ல.'
        : 'The riskiest street on this route has very little flood risk in the data held; that describes the data, not the road.',
  AdviceReason.limitsNotMet =>
    ta
        ? 'வரம்புகள் அனைத்தையும் பூர்த்தி செய்யும் வழி இல்லை; எனவே வழக்கமான வழி காட்டப்படுகிறது.'
        : 'No route meets all the limits set, so the usual route is shown.',
  AdviceReason.accidentOnRoute =>
    ta
        ? 'இந்த வழியில் நேரடி விபத்து அறிக்கை ஒன்று உள்ளது.'
        : 'A live accident report lies on this route.',
  AdviceReason.restrictedAvoided =>
    ta
        ? 'வரம்புகளால் மூடப்பட்ட சாலையைப் பயன்படுத்தும் வேகமான வழி விடப்பட்டது.'
        : 'A faster route was left out because it uses a road closed by the limits set.',
};

// --- intents ----------------------------------------------------------------

List<String> _why(_Ctx c, bool ta, List<String> facts) {
  final out = <String>[_deltaSentence(c, ta, facts)];
  final edges = c.trace.alternatives.isEmpty
      ? const <BlockingEdge>[]
      : c.trace.alternatives.first.blockingEdges;
  if (edges.isNotEmpty) {
    final e = edges.first;
    facts
      ..add('alternatives[0].blocking_edges[0].street_name')
      ..add('alternatives[0].blocking_edges[0].newest_observation_age_s');
    out.add(
      ta
          ? 'அது ${_avoidedOne(c, e, true)}.'
          : 'It leaves out ${_avoidedOne(c, e, false)}.',
    );
  }
  facts.add('confidence_band');
  out.add(_confidenceSentence(c, ta));
  return out;
}

String _confidenceSentence(_Ctx c, bool ta) {
  return switch (c.trace.confidenceBand) {
    ConfidenceBand.high =>
      ta
          ? 'இந்த வழிக்கான தரவு நம்பிக்கை அதிகம்.'
          : 'Hazard confidence for this route is high.',
    ConfidenceBand.moderate =>
      ta
          ? 'இந்த வழிக்கான தரவு நம்பிக்கை மிதமானது.'
          : 'Hazard confidence for this route is moderate.',
    ConfidenceBand.low => ta ? 'இந்த வழிக்கு சமீபத்திய தரவு குறைவு.' : 'Hazard confidence for this route is low: there is limited recent hazard data for parts of it.',
    ConfidenceBand.stale => ta ? 'இந்த வழியின் சில பகுதிகளின் தரவு பழையது.' : 'Hazard confidence for this route is stale: the most recent hazard data for parts of it is out of date.',
  };
}

List<String> _timeDistance(_Ctx c, bool ta, List<String> facts) {
  facts
    ..add('chosen.distance_m')
    ..add('chosen.free_flow_duration_s');
  final m = c.minutes;
  final out = <String>[];
  if (ta) {
    out.add(
      'வழி ${c.id} சுமார் ${c.km} கி.மீ நீளம்; இந்த பயண முறையில் தடையின்றி ஓடும் போக்குவரத்தில் '
      '${m <= 0 ? 'ஒரு நிமிடத்துக்கும் குறைவான நேரம்' : 'சுமார் $m நிமிடங்கள்'} ஆகும்.',
    );
    if (c.penaltyMinutes >= 1) {
      facts.add('chosen.hazard_time_penalty_s');
      out.add(
        'ஆபத்து தாமதங்கள் சுமார் ${c.penaltyMinutes} நிமிடங்கள் சேர்க்கும்.',
      );
    }
  } else {
    out.add(
      'Route ${c.id} is about ${c.km} km long and takes '
      '${m <= 0 ? 'under a minute' : 'about ${_plural(m, 'minute')}'} in free-flowing conditions for this travel mode.',
    );
    if (c.penaltyMinutes >= 1) {
      facts.add('chosen.hazard_time_penalty_s');
      out.add(
        'Hazard delays add about ${_plural(c.penaltyMinutes, 'minute')}.',
      );
    }
  }
  return out;
}

List<String> _alternatives(_Ctx c, bool ta, List<String> facts) {
  final out = <String>[_deltaSentence(c, ta, facts)];
  for (final a in c.trace.alternatives.take(2)) {
    final why = switch (a.rejectedBecause) {
      RejectedBecause.chanceConstraint =>
        ta
            ? 'அதன் ஒரு பகுதி அங்கு பதிவான வெள்ள ஆபத்தால் நீக்கப்பட்டது'
            : 'part of it was removed because of the flood risk reported there',
      RejectedBecause.higherCost =>
        ta
            ? 'ஆபத்து அபராதத்தைச் சேர்த்த பிறகு அது மொத்தத்தில் மோசமாக இருந்தது'
            : 'with the hazard penalty counted, it came out worse overall',
      RejectedBecause.restricted =>
        ta
            ? 'அது வரம்புகளால் அல்லது உங்கள் தேர்வால் மூடப்பட்ட சாலையைப் பயன்படுத்துகிறது'
            : 'it uses a road closed by the limits of your travel mode or by your own choice',
    };
    out.add(
      ta
          ? 'வழி ${a.routeId} விடப்பட்டது: $why.'
          : 'Route ${a.routeId} was left out: $why.',
    );
  }
  return out;
}

List<String> _avoided(_Ctx c, bool ta, List<String> facts) {
  final edges = _avoidedEdges(c).take(3).toList();
  final restricted = c.trace.alternatives.any(
    (a) => a.rejectedBecause == RejectedBecause.restricted,
  );
  final out = <String>[];
  if (edges.isEmpty) {
    out.add(
      ta
          ? 'அறிக்கையிடப்பட்ட ஆபத்துக்காக எந்த வேகமான வழியும் விடப்படவில்லை.'
          : 'No route was left out because of a hazard in the data held.',
    );
  } else {
    for (var i = 0; i < edges.length; i++) {
      facts
        ..add('alternatives[].blocking_edges[$i].street_name')
        ..add('alternatives[].blocking_edges[$i].newest_observation_age_s');
    }
    final list = edges.map((e) => _avoidedOne(c, e, ta)).join(ta ? '; ' : '; ');
    out.add(
      ta
          ? 'இவை காரணமாக வேகமான வழிகள் விடப்பட்டன: $list.'
          : 'The faster routes were left out because of these: $list.',
    );
  }
  if (restricted) {
    out.add(
      ta
          ? 'சில வழிகள் வரம்புகளால் மூடப்பட்ட சாலைகளைப் பயன்படுத்துவதால் விடப்பட்டன.'
          : 'There are routes that were left out because they use roads closed by the limits of your travel mode or by your own choice.',
    );
  }
  return out;
}

List<String> _hazard(_Ctx c, bool ta, List<String> facts) {
  facts.add('chosen.worst_edge_p');
  final a = c.advice;
  final out = <String>[
    ta
        ? 'எங்களிடம் உள்ள தரவில் வழி ${c.id} இன் வெள்ள ஆபத்து ${_riskWord(a.riskLevel, true)}.'
        : 'On the data held, flood risk on Route ${c.id} is rated ${_riskWord(a.riskLevel, false)}.',
    for (final r in a.reasons) _reason(r, ta),
    ta
        ? 'இதன் பின்னாலுள்ள தரவு ${_evidenceWord(a.evidence, true)}.'
        : 'The evidence behind this is ${_evidenceWord(a.evidence, false)}.',
    ta ? _taGuide : _enGuide,
  ];
  return out;
}

List<String> _isSafe(_Ctx c, bool ta, List<String> facts) {
  facts
    ..add('chosen.worst_edge_p')
    ..add('confidence_band');
  final a = c.advice;
  return [
    ta
        ? 'சாலையின் நிலையை என்னால் உறுதிப்படுத்த முடியாது; எனவே செல்வதற்கு அனுமதி தர முடியாது.'
        : 'I cannot confirm the condition of any road, so I cannot tell you whether to go.',
    ta
        ? 'என்னால் காட்ட முடிவது உங்கள் வழியின் ஆபத்து நிலை மட்டுமே: எங்களிடம் உள்ள தரவில் வழி ${c.id} இன் வெள்ள ஆபத்து ${_riskWord(a.riskLevel, true)}, அதன் பின்னாலுள்ள தரவு ${_evidenceWord(a.evidence, true)}.'
        : 'The most I can show is the risk on your route: the data held rates flood risk on Route ${c.id} as ${_riskWord(a.riskLevel, false)}, with ${_evidenceWord(a.evidence, false)} evidence behind it.',
    ta
        ? 'சாலையை நீங்களே சரிபார்த்து, உள்ளூர் அறிவுறுத்தல்களைப் பின்பற்றுங்கள்.'
        : 'You should check the road yourself and follow local advice.',
    ta ? _taGuide : _enGuide,
  ];
}

List<String> _shouldGo(_Ctx c, bool ta, List<String> facts) {
  facts.add('confidence_band');
  final a = c.advice;
  final action = switch (a.bestAction) {
    AdviceAction.proceedWithCare =>
      ta
          ? 'மிகுந்த கவனத்துடன் மட்டுமே பயணிக்கவும்'
          : 'travel only with extra care',
    AdviceAction.wait => ta ? 'முடிந்தால் காத்திருக்கவும்' : 'wait if you can',
    AdviceAction.avoid =>
      ta
          ? 'வேறு வழி இருந்தால் இந்த வழியைத் தவிர்க்கவும்'
          : 'choose another way if you have one',
  };
  return [
    ta
        ? 'இந்த பயணத்துக்கான ஆலோசனை: $action.'
        : 'For this trip the advice is to $action.',
    for (final r in a.reasons) _reason(r, ta),
    ta
        ? 'இதன் பின்னாலுள்ள தரவு ${_evidenceWord(a.evidence, true)}.'
        : 'The evidence behind this is ${_evidenceWord(a.evidence, false)}.',
    ta ? _taGuide : _enGuide,
  ];
}

List<String> _confidence(_Ctx c, bool ta, List<String> facts) {
  facts.add('confidence_band');
  final out = <String>[
    _confidenceSentence(c, ta),
    ta
        ? 'ஒட்டுமொத்தமாக இந்த ஆலோசனையின் பின்னாலுள்ள தரவு ${_evidenceWord(c.advice.evidence, true)}.'
        : 'The evidence behind the advice, overall, is ${_evidenceWord(c.advice.evidence, false)}.',
  ];
  final withObs = _avoidedEdges(c).where((e) => e.hasObservation).toList();
  if (withObs.isNotEmpty) {
    final newest = withObs
        .map((e) => e.newestObservationAgeSeconds)
        .reduce((a, b) => a < b ? a : b);
    final m = (newest / 60).round();
    facts.add('alternatives[].blocking_edges[].newest_observation_age_s');
    out.add(
      ta
          ? (m <= 0
                ? 'விடப்பட்ட தெருக்களில் புதிய அறிக்கை சற்று முன் வந்தது.'
                : 'விடப்பட்ட தெருக்களில் புதிய அறிக்கை $m நிமிடங்கள் பழையது.')
          : (m <= 0
                ? 'The newest report on a street that was left out arrived moments ago.'
                : 'The newest report on a street that was left out is ${_plural(m, 'minute')} old.'),
    );
  }
  out.add(ta ? _taGuide : _enGuide);
  return out;
}

List<String> _dataGaps(_Ctx c, bool ta, List<String> facts) {
  final gaps = c.trace.dataGaps;
  if (gaps.isEmpty) {
    return [
      ta
          ? 'இந்த வழியில் தரவு இல்லாத பகுதி எதுவும் குறிக்கப்படவில்லை; இது சாலையின் தற்போதைய நிலையைப் பற்றி எதுவும் சொல்லாது.'
          : 'No corridor on this route was marked as lacking data; that says nothing about conditions on the ground.',
    ];
  }
  for (var i = 0; i < gaps.length; i++) {
    facts.add('data_gaps[$i].corridor');
  }
  final names = gaps.map((g) => g.corridor).join(', ');
  return [
    ta
        ? '$names பகுதிகளுக்கு சமீபத்திய தரவு இல்லை; தரவு இல்லை என்பதற்காக அங்கு ஆபத்து இருக்காது என்று பொருள் அல்ல.'
        : 'No recent hazard data is available for $names; a lack of data is not the same as a lack of hazard.',
  ];
}

String _classWord(UserClass u, bool ta) => switch (u) {
  UserClass.commuter => ta ? 'கார்' : 'car',
  UserClass.pedestrian => ta ? 'நடந்து செல்வோர்' : 'on foot',
  UserClass.cyclist => ta ? 'சைக்கிள்' : 'bicycle',
  UserClass.emergency => ta ? 'அவசர வாகனம்' : 'emergency vehicle',
};

List<String> _travelMode(_Ctx c, bool ta, List<String> facts) {
  facts.add('user_class');
  final w = _classWord(c.trace.userClass, ta);
  return [
    ta
        ? 'இந்த வழி "$w" பயண முறைக்காக கணக்கிடப்பட்டது.'
        : 'This route was calculated for the $w travel mode.',
    ta
        ? 'வேறு பயண முறை வழியை எப்படி மாற்றும் என்று பார்க்க, வழித் திரையில் பயண முறையை மாற்றுங்கள்; அந்த முறையின் சொந்த வரம்புகளுடனும் எச்சரிக்கையுடனும் வழி மீண்டும் கணக்கிடப்படும். கார், சைக்கிள், நடந்து, அவசர வாகனம் ஆகியவை உள்ளன.'
        : 'You can see how another mode changes the route by switching the travel mode on the route screen; the route is then calculated again with that mode\'s own limits and caution. The modes are car, bicycle, on foot and emergency vehicle.',
  ];
}

List<String> _eventState(_Ctx c, bool ta, List<String> facts) {
  facts.add('event_state');
  final s = switch (c.eventState) {
    EventState.dry =>
      ta
          ? 'நிகழ்வு நிலை அமைதி: மழை நிகழ்வு அறிவிக்கப்படவில்லை; எனவே வெள்ள வரைபடம் பயன்படுத்தப்படவில்லை, ஆனால் அறிக்கைகள் பயன்படுத்தப்படுகின்றன.'
          : 'The event state is quiet: no rain event has been declared, so the flood map is not applied, though reports still are.',
    EventState.watch =>
      ta
          ? 'மழை கண்காணிப்பு அமலில் உள்ளது; எனவே இந்த வழிக்கு வெள்ள வரைபடம் பயன்படுத்தப்படுகிறது.'
          : 'A rain watch is in force, so the flood map is applied to this route.',
    EventState.active =>
      ta
          ? 'வெள்ள நிகழ்வு நடந்து வருகிறது; எனவே இந்த வழிக்கு வெள்ள வரைபடம் பயன்படுத்தப்படுகிறது.'
          : 'A flood event is under way, so the flood map is applied to this route.',
  };
  return [
    s,
    ta
        ? 'என்னிடம் வானிலை முன்னறிவிப்பு இல்லை.'
        : 'I do not have a weather forecast.',
  ];
}

List<String> _accidents(_Ctx c, bool ta, List<String> facts) {
  final f = c.fact('accident_reports_on_route');
  final out = <String>[];
  if (f == null) {
    out.add(
      ta
          ? 'விபத்து அறிக்கைகள் இந்த வழியின் தரவில் சேர்க்கப்படவில்லை.'
          : 'This route\'s data does not include accident reports.',
    );
  } else {
    facts.add('context_facts.accident_reports_on_route');
    final n = f.value is num ? (f.value! as num).toInt() : 0;
    out.add(
      n > 0
          ? (ta
                ? 'கிடைக்கும் தரவில் இந்த வழியில் நேரடி விபத்து அறிக்கை உள்ளது.'
                : 'A live accident report lies on this route in the data held.')
          : (ta
                ? 'கிடைக்கும் தரவில் இந்த வழியில் நேரடி விபத்து அறிக்கை இல்லை; அறிக்கைகள் முழுமையற்றவை, எனவே இது குறைவாகவே சொல்கிறது.'
                : 'No live accident report lies on this route in the data held; reports are partial, so this says little.'),
    );
  }
  out.add(
    c.fact('traveller_avoids') != null
        ? (ta
              ? 'இந்த பயணத்துக்கு புகாரளிக்கப்பட்ட விபத்துகளிலிருந்து விலகி இருக்க தேர்ந்தெடுத்தீர்கள்.'
              : 'You chose to keep away from reported accidents on this trip.')
        : (ta
              ? 'இந்த பயணத்துக்கு விபத்துகளிலிருந்து விலகும் தேர்வு இயக்கப்படவில்லை.'
              : 'The option to keep away from reported accidents was off for this trip.'),
  );
  return out;
}

List<String> _limits(_Ctx c, bool ta, List<String> facts) {
  final out = <String>[];
  final m = c.fact('mode_limits');
  if (m != null) {
    facts.add('context_facts.mode_limits');
    out.add(
      ta
          ? 'இந்த வழிக்கு பயண முறையின் வரம்புகள் பயன்படுத்தப்பட்டன.'
          : 'The ${m.label} were applied to this route.',
    );
  } else {
    out.add(
      ta
          ? 'இந்த வழிக்கு பயண முறை வரம்புகள் எதுவும் பயன்படுத்தப்படவில்லை.'
          : 'No travel-mode limits were applied to this route.',
    );
  }
  if (c.fact('restricted_segments') != null) {
    facts.add('context_facts.restricted_segments');
    out.add(
      ta
          ? 'அந்த வரம்புகளால் மூடப்பட்ட சில சாலைகள் விடப்பட்டன.'
          : 'The roads closed by those limits were left out.',
    );
  }
  if (c.fact('limits_not_met') != null) {
    facts.add('context_facts.limits_not_met');
    out.add(
      ta
          ? 'வரம்புகள் அனைத்தையும் பூர்த்தி செய்யும் வழி இல்லை; எனவே வழக்கமான வழி காட்டப்படுகிறது.'
          : 'No route meets all of the limits, so the usual route is shown.',
    );
  }
  return out;
}

List<String> _departure(_Ctx c, bool ta, List<String> facts) => [
  ta
      ? 'புறப்பட சிறந்த நேரத்தை இந்த செயலி இன்னும் பரிந்துரைப்பதில்லை.'
      : 'This app does not yet advise on the best time to leave.',
  ta
      ? 'இங்குள்ள ஆலோசனை இந்த வழி கணக்கிடப்பட்ட தருணத்தின் நிலையைக் காட்டுகிறது; புறப்படும் நேரம் நெருங்கும்போது மீண்டும் கேளுங்கள்.'
      : 'The advice here reflects conditions as of the moment this route was calculated; ask again closer to your departure.',
];

List<String> _offline(_Ctx c, bool ta, List<String> facts) {
  facts.add('mode');
  return [
    c.trace.mode == RoutingMode.offline
        ? (ta
              ? 'இந்த வழி ஏற்கனவே சேமிக்கப்பட்ட தரவிலிருந்து மட்டுமே, சர்வரிலிருந்து நேரடி புதுப்பிப்பு இல்லாமல் கணக்கிடப்பட்டது.'
              : 'This route was calculated from the data already stored here, with no live update from a server.')
        : (ta
              ? 'இந்த வழி சேமிக்கப்பட்ட தரவுடன் சர்வரின் நேரடி அறிக்கைகளையும் பார்த்து கணக்கிடப்பட்டது.'
              : 'This route was checked against live reports from the server as well as the data stored here.'),
  ];
}

List<String> _how(_Ctx c, bool ta, List<String> facts) => [
  ta
      ? 'இந்த செயலி முதலில் விரைவான வழியைக் கண்டுபிடிக்கிறது; பிறகு வெள்ள ஆபத்து அதிகமுள்ள தெருக்களுக்கு வெள்ள அபாய வரைபடத்தையும் சமீபத்திய அறிக்கைகளையும் பயன்படுத்தி அபராதம் சேர்க்கிறது; இந்த அபராதம் ஒவ்வொரு பயண முறைக்கும் வேறுபடும். புதிய அறிக்கைகள் பழையவற்றை விட அதிக எடை பெறுகின்றன. இது தண்ணீரின் ஆழத்தை நேரலையில் அளப்பதில்லை; எந்த சாலை பற்றியும் உறுதிமொழி தருவதில்லை.'
      : 'This app finds a quick route, then adds a penalty to streets with a higher flood risk, using the flood hazard map and recent reports, and it weighs that penalty differently for each travel mode. The newer reports count for more than the older ones. It does not measure water depth live, and it makes no promise about any road.',
];

List<String> _help(_Ctx c, bool ta, List<String> facts) => [
  ta
      ? 'இந்த வழியைப் பற்றி கேளுங்கள்: ஏன் தேர்ந்தெடுக்கப்பட்டது, எவ்வளவு நேரம் ஆகும், வேறு வழிகள், விடப்பட்ட தெருக்கள், வெள்ள ஆபத்து, தரவு எவ்வளவு நம்பகமானது, எந்த தரவு இல்லை, விபத்துகள், பயண முறை, அல்லது இணையம் இல்லாமல் வேலை செய்யுமா என்பது.'
      : 'You can ask about this route: why it was chosen, how long it takes, which other routes exist, which streets were left out, the flood risk, how sure the data is, what data is missing, accidents, the travel mode, or whether it needs a network connection.',
];

List<String> _outOfScope(_Ctx c, bool ta, List<String> facts) => [
  ta
      ? 'திரையில் உள்ள வழியைப் பற்றிய கேள்விகளுக்கு மட்டுமே என்னால் பதில் சொல்ல முடியும். ஏன் தேர்ந்தெடுக்கப்பட்டது, எவ்வளவு நேரம் ஆகும் அல்லது தரவு எவ்வளவு நம்பகமானது என்று கேட்டுப் பாருங்கள்.'
      : 'I can only answer questions about the route on screen. You can try asking why it was chosen, how long it takes or how sure the data is.',
];
