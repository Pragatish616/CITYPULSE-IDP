/// User-facing text in English and Tamil.
///
/// **The Tamil text is a first draft and has NOT been reviewed by a native
/// speaker.** It must be reviewed (and the disclaimer translated by someone
/// accountable for it) before release; the explanation sentences themselves are
/// English-only for now because Tier 0 templates exist only in English
/// (`pulse_explain` `Explanation.locale`).
///
/// ADR-011 / PLAN.md §10.2: no UI string may say a road is safe, dry, clear or
/// "go ahead". The only occurrence of "safe" is inside the verbatim ADR-011
/// disclaimer (`disclaimer_text.dart`), which negates it. `strings_test.dart`
/// enforces this on every string in both languages.
library;

import 'package:pulse_router/pulse_router.dart' show CityConfig;

/// Message keys. Adding one without text in both languages fails the test.
enum Msg {
  appName,
  navMap,
  navHelp,
  navSettings,
  whereFrom,
  whereTo,
  searchHint,
  setStart,
  setDestination,
  reportHere,
  useMapCentre,
  planRoute,
  planning,
  clear,
  swap,
  routeTime,
  routeDistance,
  longerThanFastest,
  sameAsFastest,
  showFastest,
  hideFastest,
  explanationHeading,
  explanationEnglishOnly,
  dataGapsNote,
  travelType,
  commuter,
  cyclist,
  pedestrian,
  emergency,
  layers,
  hazardMap,
  hazardMapNote,
  watchlist,
  watchlistNote,
  legend,
  legendMapOnly,
  legendReported,
  legendAvoided,
  eventDry,
  eventWatch,
  eventActive,
  rainLineNone,
  rainLineNow,
  rainLineEarlier,
  rainLineStale,
  rainClassLight,
  rainClassModerate,
  rainClassHeavy,
  rainClassViolent,
  rainClassUnknown,
  rainSheetTitle,
  rainRow3h,
  rainRowPeak,
  rainRowImage,
  rainRowState,
  rainSourceRain,
  rainSourceManual,
  rainSourceFallback,
  rainSourceConfigured,
  rainCaveat,
  errorOriginOutside,
  errorDestinationOutside,
  errorSameLocation,
  errorNoRoute,
  startFarFromRoad,
  endFarFromRoad,
  adviceProceed,
  adviceWait,
  adviceAvoid,
  riskLower,
  riskModerate,
  riskHigh,
  evidenceStrong,
  evidenceSome,
  evidenceLittle,
  reasonHighRiskStreet,
  reasonSomeRiskStreets,
  reasonFloodedAlternatives,
  reasonLittleData,
  reasonStaleData,
  reasonNoEvent,
  reasonNoHazardFound,
  choiceClose,
  adviceHedge,
  errorNetwork,
  errorServer,
  errorNotReady,
  tryAgain,
  loadingMap,
  reportTitle,
  reportWhat,
  reportFlooded,
  reportStanding,
  reportCleared,
  reportDepth,
  depthUnknown,
  depthAnkle,
  depthKnee,
  depthAbove,
  reportLocation,
  reportLocationCentre,
  reportLocationHint,
  reportPrivacy,
  reportSubmit,
  reportSent,
  reportQueued,
  reportFailed,
  helpTitle,
  helpEmergency,
  helpAboutData,
  helpAboutDataBody,
  helpLimits,
  helpLimitsBody,
  settingsTitle,
  settingsLanguage,
  settingsCompute,
  computeAuto,
  computeDevice,
  computeServer,
  settingsPrivacy,
  settingsResetId,
  settingsResetIdDone,
  settingsVersion,
  settingsComputedOn,
  mapAttribution,
  settingsLicences,
  settingsDataSources,
  dataSourcesBody,
  onDevice,
  onServer,
  cancel,
  close,
}

/// A language the UI can be shown in.
enum AppLanguage {
  /// English.
  en('English'),

  /// Tamil (draft, unreviewed).
  ta('தமிழ்');

  const AppLanguage(this.nativeName);

  /// The language's own name.
  final String nativeName;

  /// Parses a stored code; unknown values give English.
  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (l) => l.name == code,
    orElse: () => AppLanguage.en,
  );
}

/// Looks strings up for one language.
class Strings {
  /// Creates the lookup for [language].
  const Strings(this.language, {this.city});

  /// The language in use.
  final AppLanguage language;

  /// The city whose name and data texts fill the `{city}`, `{hazard_note}`, `{about_data}` and
  /// `{data_credit}` placeholders (ADR-018). Without one the placeholders stay as written.
  final CityConfig? city;

  /// The text for [key], with the city's texts filled in.
  String call(Msg key) {
    final text = (language == AppLanguage.ta ? _ta : _en)[key]!;
    final c = city;
    if (c == null || !text.contains('{')) return text;
    final code = language == AppLanguage.ta ? 'ta' : 'en';
    return text
        .replaceAll('{hazard_note}', c.hazardNote.forLanguage(code))
        .replaceAll('{about_data}', c.aboutData.forLanguage(code))
        .replaceAll('{data_credit}', c.dataCredit.forLanguage(code))
        .replaceAll('{city}', c.name.forLanguage(code));
  }

  /// "12 min" / "12 நிமி"; from 90 minutes up, hours and minutes ("2 h 10 min").
  String minutes(int n) {
    final ta = language == AppLanguage.ta;
    if (n < 90) return ta ? '$n நிமி' : '$n min';
    final h = n ~/ 60;
    final m = n % 60;
    if (ta) return m == 0 ? '$h மணி' : '$h மணி $m நிமி';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// "9.3 km".
  String kilometres(double metres) =>
      '${(metres / 1000).toStringAsFixed(1)} ${language == AppLanguage.ta ? 'கி.மீ' : 'km'}';

  /// Substitutes `{km}` in [key]'s text with [metres] as kilometres to one decimal.
  String withKm(Msg key, double metres) =>
      call(key).replaceAll('{km}', (metres / 1000).toStringAsFixed(1));

  /// Substitutes `{n}` in [key]'s text.
  String withNumber(Msg key, int n) => call(key).replaceAll('{n}', '$n');

  /// Substitutes each `{name}` in [key]'s text with its value.
  String fill(Msg key, Map<String, String> values) {
    var text = call(key);
    values.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }
}

/// Every English string, exposed for the tests.
Map<Msg, String> get englishStrings => _en;

/// Every Tamil string, exposed for the tests.
Map<Msg, String> get tamilStrings => _ta;

const Map<Msg, String> _en = {
  Msg.appName: 'CityPulse',
  Msg.navMap: 'Map',
  Msg.navHelp: 'Help',
  Msg.navSettings: 'Settings',
  Msg.whereFrom: 'Start',
  Msg.whereTo: 'Where to?',
  Msg.searchHint: 'Search a street name',
  Msg.setStart: 'Start here',
  Msg.setDestination: 'Go here',
  Msg.reportHere: 'Report water here',
  Msg.useMapCentre: 'Use map centre',
  Msg.planRoute: 'Plan route',
  Msg.planning: 'Planning route…',
  Msg.clear: 'Clear',
  Msg.swap: 'Swap start and destination',
  Msg.routeTime: 'Travel time',
  Msg.routeDistance: 'Distance',
  Msg.longerThanFastest: '{n} min longer than the fastest route',
  Msg.sameAsFastest: 'This is also the fastest route.',
  Msg.showFastest: 'Show fastest route',
  Msg.hideFastest: 'Hide fastest route',
  Msg.explanationHeading: 'Why this route',
  Msg.explanationEnglishOnly: 'Explanation (English)',
  Msg.dataGapsNote: 'Absence of data is not the same as absence of hazard.',
  Msg.travelType: 'Travelling by',
  Msg.commuter: 'Car',
  Msg.cyclist: 'Bicycle',
  Msg.pedestrian: 'On foot',
  Msg.emergency: 'Emergency vehicle',
  Msg.layers: 'Map layers',
  Msg.hazardMap: 'Flood-hazard map',
  Msg.hazardMapNote: '{hazard_note}',
  Msg.watchlist: 'Hotspot candidates (unverified)',
  Msg.watchlistNote:
      'Clusters of high-hazard zones that may become the watchlist. A person '
      'who knows the city has not yet checked them.',
  Msg.legend: 'Legend',
  Msg.legendMapOnly: 'Hazard map only, no report (dashed)',
  Msg.legendReported: 'A report exists (solid)',
  Msg.legendAvoided: 'Hazard this route avoids',
  Msg.eventDry:
      'No flood event is in force, so the hazard map is not applied to routes. '
      'Reports still count.',
  Msg.eventWatch: 'Flood watch: the hazard map is applied to routes.',
  Msg.eventActive: 'Flood event: the hazard map is applied to routes.',
  Msg.rainLineNone:
      'Rain by satellite over {area}: none in the last 3 h · image {age} old',
  Msg.rainLineNow: 'Rain by satellite over {area}: {class} now · {mm} mm in the last 3 h · image {age} old',
  Msg.rainLineEarlier: 'Rain by satellite over {area}: none now · {mm} mm earlier in the last 3 h · image {age} old',
  Msg.rainLineStale: 'Rain by satellite over {area}: the data is out of date',
  Msg.rainClassLight: 'light',
  Msg.rainClassModerate: 'moderate',
  Msg.rainClassHeavy: 'heavy',
  Msg.rainClassViolent: 'very intense',
  Msg.rainClassUnknown: 'some',
  Msg.rainSheetTitle: 'Satellite rain and the flood-event state',
  Msg.rainRow3h: 'Last 3 hours (average over the area)',
  Msg.rainRowPeak: 'Strongest spot',
  Msg.rainRowImage: 'Satellite image',
  Msg.rainRowState: 'Flood-event state',
  Msg.rainSourceRain: 'Set automatically from satellite rain.',
  Msg.rainSourceManual: 'Set by an operator.',
  Msg.rainSourceFallback:
      'Rain data was missing or out of date, so the default setting is used.',
  Msg.rainSourceConfigured: 'Fixed by the service setting.',
  Msg.rainCaveat: 'A satellite estimate in cells of about 10 km, hours behind real time. Rain is not flooding, and this says nothing about any one street.',
  Msg.errorOriginOutside:
      'The start point is outside the mapped {city} road network.',
  Msg.errorDestinationOutside:
      'The destination is outside the mapped {city} road network.',
  Msg.errorSameLocation: 'The start and destination are the same place.',
  Msg.errorNoRoute: 'No road connects these two places.',
  Msg.adviceProceed: 'Proceed with care',
  Msg.adviceWait: 'Wait if you can',
  Msg.adviceAvoid: 'Avoid this route',
  Msg.riskLower: 'Lower risk',
  Msg.riskModerate: 'Moderate risk',
  Msg.riskHigh: 'High risk',
  Msg.evidenceStrong: 'Strong evidence',
  Msg.evidenceSome: 'Some evidence',
  Msg.evidenceLittle: 'Little evidence',
  Msg.reasonHighRiskStreet: 'A street on this route has high flood risk.',
  Msg.reasonSomeRiskStreets: 'Some streets on this route have flood risk.',
  Msg.reasonFloodedAlternatives:
      'Faster routes through flooded streets were left out.',
  Msg.reasonLittleData: 'Little recent data covers this route.',
  Msg.reasonStaleData: 'The data for this route is out of date.',
  Msg.reasonNoEvent:
      'No flood event is under way, so the flood map is not applied.',
  Msg.reasonNoHazardFound:
      'No flood hazard was found on this route in the data we have.',
  Msg.choiceClose: 'Another route is a close call.',
  Msg.adviceHedge: 'A guide from the data we have, not a guarantee.',
  Msg.startFarFromRoad: 'Your start is {km} km from the nearest road on this map. The route begins there.',
  Msg.endFarFromRoad: 'Your destination is {km} km from the nearest road on this map. The route ends there.',
  Msg.errorNetwork:
      'Could not reach the routing service. Check your connection.',
  Msg.errorServer: 'The routing service had a problem. Try again.',
  Msg.errorNotReady: 'The map data is still loading.',
  Msg.tryAgain: 'Try again',
  Msg.loadingMap: 'Loading the {city} road network…',
  Msg.reportTitle: 'Report water on the road',
  Msg.reportWhat: 'What do you see?',
  Msg.reportFlooded: 'Flooded road',
  Msg.reportStanding: 'Standing water',
  Msg.reportCleared: 'The water has cleared',
  Msg.reportDepth: 'How deep? (your estimate)',
  Msg.depthUnknown: 'Not sure',
  Msg.depthAnkle: 'Ankle deep',
  Msg.depthKnee: 'Knee deep',
  Msg.depthAbove: 'Above the knee',
  Msg.reportLocation: 'Location',
  Msg.reportLocationCentre: 'Centre of the map',
  Msg.reportLocationHint:
      'To report a different spot, close this, tap the road on the map and '
      'choose "Report water here".',
  Msg.reportPrivacy:
      'Only the spot you choose is sent, rounded to about 10 metres, with a '
      'random install code that is not linked to you. No name, photo or '
      'free text.',
  Msg.reportSubmit: 'Send report',
  Msg.reportSent: 'Report sent. Thank you.',
  Msg.reportQueued:
      'Saved on this device. It will be sent when you are back online.',
  Msg.reportFailed: 'The report was not accepted. Please check and try again.',
  Msg.helpTitle: 'Help and about',
  Msg.helpEmergency: 'In an emergency call 112.',
  Msg.helpAboutData: 'About the data',
  Msg.helpAboutDataBody: '{about_data}',
  Msg.helpLimits: 'What CityPulse cannot do',
  Msg.helpLimitsBody:
      'It does not know current water depth on any street. It shows relative '
      'risk and how old the evidence is. The condition of a road with no '
      'report is simply unknown. It is a research prototype.',
  Msg.settingsTitle: 'Settings',
  Msg.settingsLanguage: 'Language',
  Msg.settingsCompute: 'Where routes are calculated',
  Msg.computeAuto: 'Automatic',
  Msg.computeDevice: 'On this device',
  Msg.computeServer: 'On the server',
  Msg.settingsPrivacy: 'Privacy',
  Msg.settingsResetId: 'Reset my anonymous install code',
  Msg.settingsResetIdDone: 'A new anonymous code was created.',
  Msg.settingsVersion: 'Version',
  Msg.settingsComputedOn: 'Calculated',
  Msg.mapAttribution:
      '© OpenStreetMap contributors (ODbL) · OpenFreeMap © OpenMapTiles',
  Msg.settingsLicences: 'Software licences',
  Msg.settingsDataSources: 'Data sources and licences',
  Msg.dataSourcesBody:
      'Roads and the base map: © OpenStreetMap contributors, Open Database '
      'Licence (ODbL), https://www.openstreetmap.org/copyright. The base map '
      'is served by OpenFreeMap using OpenMapTiles. The routing data in this app '
      'is a database derived from OpenStreetMap and is shared under the same '
      'licence.\n\n'
      '{data_credit}\n\n'
      'This app shows relative risk and how old the evidence is, and nothing '
      'more. It makes no promise about any road.',
  Msg.onDevice: 'on this device',
  Msg.onServer: 'on the server',
  Msg.cancel: 'Cancel',
  Msg.close: 'Close',
};

// DRAFT, unreviewed Tamil. See the library comment.
const Map<Msg, String> _ta = {
  Msg.appName: 'CityPulse',
  Msg.navMap: 'வரைபடம்',
  Msg.navHelp: 'உதவி',
  Msg.navSettings: 'அமைப்புகள்',
  Msg.whereFrom: 'தொடக்கம்',
  Msg.whereTo: 'எங்கே செல்ல வேண்டும்?',
  Msg.searchHint: 'தெருவின் பெயரைத் தேடுங்கள்',
  Msg.setStart: 'இங்கிருந்து தொடங்கு',
  Msg.setDestination: 'இங்கே செல்ல வேண்டும்',
  Msg.reportHere: 'இங்குள்ள தண்ணீரைப் புகாரளி',
  Msg.useMapCentre: 'வரைபட மையத்தைப் பயன்படுத்து',
  Msg.planRoute: 'வழியைத் திட்டமிடு',
  Msg.planning: 'வழியைக் கணக்கிடுகிறது…',
  Msg.clear: 'அழி',
  Msg.swap: 'தொடக்கத்தையும் இலக்கையும் மாற்று',
  Msg.routeTime: 'பயண நேரம்',
  Msg.routeDistance: 'தூரம்',
  Msg.longerThanFastest: 'விரைவான வழியை விட {n} நிமிடம் அதிகம்',
  Msg.sameAsFastest: 'இதுவே விரைவான வழியும் ஆகும்.',
  Msg.showFastest: 'விரைவான வழியைக் காட்டு',
  Msg.hideFastest: 'விரைவான வழியை மறை',
  Msg.explanationHeading: 'இந்த வழி ஏன்',
  Msg.explanationEnglishOnly: 'விளக்கம் (ஆங்கிலத்தில்)',
  Msg.dataGapsNote: 'தரவு இல்லாதது ஆபத்து இல்லை என்பதற்குச் சமமல்ல.',
  Msg.travelType: 'பயண முறை',
  Msg.commuter: 'கார்',
  Msg.cyclist: 'மிதிவண்டி',
  Msg.pedestrian: 'நடந்து',
  Msg.emergency: 'அவசர வாகனம்',
  Msg.layers: 'வரைபட அடுக்குகள்',
  Msg.hazardMap: 'வெள்ள அபாய வரைபடம்',
  Msg.hazardMapNote: '{hazard_note}',
  Msg.watchlist: 'முக்கிய இடங்கள் (சரிபார்க்கப்படாதவை)',
  Msg.watchlistNote:
      'அதிக அபாய மண்டலங்களின் தொகுப்புகள். நகரத்தை அறிந்த ஒருவர் இன்னும் '
      'இவற்றைச் சரிபார்க்கவில்லை.',
  Msg.legend: 'குறிவிளக்கம்',
  Msg.legendMapOnly: 'அபாய வரைபடம் மட்டும், புகார் இல்லை (புள்ளிக்கோடு)',
  Msg.legendReported: 'புகார் உள்ளது (தொடர்கோடு)',
  Msg.legendAvoided: 'இந்த வழி தவிர்க்கும் அபாயம்',
  Msg.eventDry:
      'தற்போது வெள்ள நிகழ்வு எதுவும் இல்லை, எனவே அபாய வரைபடம் வழிகளுக்குப் '
      'பயன்படுத்தப்படவில்லை. புகார்கள் தொடர்ந்து கணக்கில் எடுக்கப்படும்.',
  Msg.eventWatch:
      'வெள்ளக் கண்காணிப்பு: அபாய வரைபடம் வழிகளுக்குப் பயன்படுத்தப்படுகிறது.',
  Msg.eventActive:
      'வெள்ள நிகழ்வு: அபாய வரைபடம் வழிகளுக்குப் பயன்படுத்தப்படுகிறது.',
  Msg.rainLineNone: '{area} பகுதியில் செயற்கைக்கோள் மழை: கடந்த 3 மணி நேரத்தில் இல்லை · படம் {age} பழையது',
  Msg.rainLineNow: '{area} பகுதியில் செயற்கைக்கோள் மழை: இப்போது {class} · கடந்த 3 மணி நேரத்தில் {mm} மி.மீ · படம் {age} பழையது',
  Msg.rainLineEarlier: '{area} பகுதியில் செயற்கைக்கோள் மழை: இப்போது இல்லை · கடந்த 3 மணி நேரத்தில் {mm} மி.மீ · படம் {age} பழையது',
  Msg.rainLineStale: '{area} பகுதியில் செயற்கைக்கோள் மழைத் தரவு காலாவதியானது',
  Msg.rainClassLight: 'லேசான',
  Msg.rainClassModerate: 'மிதமான',
  Msg.rainClassHeavy: 'கனமான',
  Msg.rainClassViolent: 'மிகக் கனமான',
  Msg.rainClassUnknown: 'சிறிது',
  Msg.rainSheetTitle: 'செயற்கைக்கோள் மழையும் வெள்ள நிகழ்வு நிலையும்',
  Msg.rainRow3h: 'கடந்த 3 மணி நேரம் (பகுதி சராசரி)',
  Msg.rainRowPeak: 'அதிக மழை பெய்யும் இடம்',
  Msg.rainRowImage: 'செயற்கைக்கோள் படம்',
  Msg.rainRowState: 'வெள்ள நிகழ்வு நிலை',
  Msg.rainSourceRain: 'செயற்கைக்கோள் மழையிலிருந்து தானாக அமைக்கப்பட்டது.',
  Msg.rainSourceManual: 'ஒரு இயக்குநரால் அமைக்கப்பட்டது.',
  Msg.rainSourceFallback: 'மழைத் தரவு இல்லை அல்லது பழையது; எனவே இயல்புநிலை அமைப்பு பயன்படுத்தப்படுகிறது.',
  Msg.rainSourceConfigured: 'சேவை அமைப்பால் நிர்ணயிக்கப்பட்டது.',
  Msg.rainCaveat: 'சுமார் 10 கி.மீ கட்டங்களில் செயற்கைக்கோள் மதிப்பீடு; நேரடி நேரத்தை விட பல மணி நேரம் பின்தங்கியது. மழை என்பது வெள்ளம் அல்ல; எந்த ஒரு தெருவைப் பற்றியும் இது எதுவும் சொல்லாது.',
  Msg.errorOriginOutside: 'தொடக்கப் புள்ளி வரைபடத்தில் உள்ள {city} சாலை வலையமைப்புக்கு வெளியே உள்ளது.',
  Msg.errorDestinationOutside:
      'இலக்கு வரைபடத்தில் உள்ள {city} சாலை வலையமைப்புக்கு வெளியே உள்ளது.',
  Msg.errorSameLocation: 'தொடக்கமும் இலக்கும் ஒரே இடம்.',
  Msg.errorNoRoute: 'இந்த இரு இடங்களையும் இணைக்கும் சாலை இல்லை.',
  Msg.adviceProceed: 'கவனத்துடன் பயணிக்கவும்',
  Msg.adviceWait: 'முடிந்தால் காத்திருக்கவும்',
  Msg.adviceAvoid: 'இந்த வழியைத் தவிர்க்கவும்',
  Msg.riskLower: 'குறைந்த ஆபத்து',
  Msg.riskModerate: 'மிதமான ஆபத்து',
  Msg.riskHigh: 'அதிக ஆபத்து',
  Msg.evidenceStrong: 'வலுவான தரவு',
  Msg.evidenceSome: 'ஓரளவு தரவு',
  Msg.evidenceLittle: 'குறைவான தரவு',
  Msg.reasonHighRiskStreet:
      'இந்த வழியில் உள்ள ஒரு தெருவில் வெள்ள ஆபத்து அதிகம்.',
  Msg.reasonSomeRiskStreets:
      'இந்த வழியில் சில தெருக்களில் வெள்ள ஆபத்து உள்ளது.',
  Msg.reasonFloodedAlternatives:
      'வெள்ளம் பாதித்த தெருக்கள் வழியான வேகமான வழிகள் தவிர்க்கப்பட்டன.',
  Msg.reasonLittleData: 'இந்த வழிக்கு சமீபத்திய தரவு குறைவு.',
  Msg.reasonStaleData: 'இந்த வழிக்கான தரவு பழையது.',
  Msg.reasonNoEvent:
      'வெள்ள நிகழ்வு இல்லாததால் வெள்ள வரைபடம் பயன்படுத்தப்படவில்லை.',
  Msg.reasonNoHazardFound:
      'எங்களிடம் உள்ள தரவில் இந்த வழியில் வெள்ள ஆபத்து எதுவும் காணப்படவில்லை.',
  Msg.choiceClose: 'மற்றொரு வழி கிட்டத்தட்ட சமமாக உள்ளது.',
  Msg.adviceHedge:
      'எங்களிடம் உள்ள தரவின் அடிப்படையிலான வழிகாட்டி; உத்தரவாதம் அல்ல.',
  Msg.startFarFromRoad: 'உங்கள் தொடக்கப் புள்ளி இந்த வரைபடத்தில் உள்ள அருகிலுள்ள சாலையிலிருந்து {km} கி.மீ தொலைவில் உள்ளது. வழி அங்கிருந்து தொடங்குகிறது.',
  Msg.endFarFromRoad: 'உங்கள் இலக்கு இந்த வரைபடத்தில் உள்ள அருகிலுள்ள சாலையிலிருந்து {km} கி.மீ தொலைவில் உள்ளது. வழி அங்கு முடிகிறது.',
  Msg.errorNetwork: 'வழி சேவையை அடைய முடியவில்லை. இணைப்பைச் சரிபார்க்கவும்.',
  Msg.errorServer: 'வழி சேவையில் சிக்கல் ஏற்பட்டது. மீண்டும் முயற்சிக்கவும்.',
  Msg.errorNotReady: 'வரைபடத் தரவு இன்னும் ஏற்றப்படுகிறது.',
  Msg.tryAgain: 'மீண்டும் முயற்சி',
  Msg.loadingMap: '{city} சாலை வலையமைப்பை ஏற்றுகிறது…',
  Msg.reportTitle: 'சாலையில் தண்ணீர் இருப்பதைப் புகாரளிக்கவும்',
  Msg.reportWhat: 'நீங்கள் என்ன பார்க்கிறீர்கள்?',
  Msg.reportFlooded: 'வெள்ளம் சூழ்ந்த சாலை',
  Msg.reportStanding: 'தேங்கிய தண்ணீர்',
  Msg.reportCleared: 'தண்ணீர் வடிந்துவிட்டது',
  Msg.reportDepth: 'எவ்வளவு ஆழம்? (உங்கள் மதிப்பீடு)',
  Msg.depthUnknown: 'தெரியவில்லை',
  Msg.depthAnkle: 'கணுக்கால் அளவு',
  Msg.depthKnee: 'முழங்கால் அளவு',
  Msg.depthAbove: 'முழங்காலுக்கு மேல்',
  Msg.reportLocation: 'இடம்',
  Msg.reportLocationCentre: 'வரைபடத்தின் மையம்',
  Msg.reportLocationHint:
      'வேறு இடத்தைப் புகாரளிக்க, இதை மூடி, வரைபடத்தில் சாலையைத் தொட்டு '
      '"இங்குள்ள தண்ணீரைப் புகாரளி" என்பதைத் தேர்ந்தெடுக்கவும்.',
  Msg.reportPrivacy:
      'நீங்கள் தேர்ந்தெடுக்கும் இடம் மட்டுமே, சுமார் 10 மீட்டருக்குச் '
      'சுருக்கப்பட்டு, உங்களுடன் தொடர்பில்லாத ஒரு சீரற்ற நிறுவல் குறியீட்டுடன் '
      'அனுப்பப்படும். பெயர், புகைப்படம், கட்டற்ற உரை எதுவும் இல்லை.',
  Msg.reportSubmit: 'புகாரை அனுப்பு',
  Msg.reportSent: 'புகார் அனுப்பப்பட்டது. நன்றி.',
  Msg.reportQueued:
      'இந்தச் சாதனத்தில் சேமிக்கப்பட்டது. இணைப்பு கிடைத்ததும் அனுப்பப்படும்.',
  Msg.reportFailed:
      'புகார் ஏற்கப்படவில்லை. சரிபார்த்து மீண்டும் முயற்சிக்கவும்.',
  Msg.helpTitle: 'உதவியும் விவரங்களும்',
  Msg.helpEmergency: 'அவசரநிலையில் 112 ஐ அழைக்கவும்.',
  Msg.helpAboutData: 'தரவு பற்றி',
  Msg.helpAboutDataBody: '{about_data}',
  Msg.helpLimits: 'CityPulse என்ன செய்ய முடியாது',
  Msg.helpLimitsBody:
      'எந்தத் தெருவிலும் தற்போதைய நீரின் ஆழம் இதற்குத் தெரியாது. இது '
      'ஒப்பீட்டு ஆபத்தையும் சான்றின் வயதையும் காட்டுகிறது. புகார் இல்லாத '
      'சாலையின் நிலை தெரியாது. இது ஓர் ஆய்வு முன்மாதிரி.',
  Msg.settingsTitle: 'அமைப்புகள்',
  Msg.settingsLanguage: 'மொழி',
  Msg.settingsCompute: 'வழிகள் எங்கே கணக்கிடப்படுகின்றன',
  Msg.computeAuto: 'தானியங்கி',
  Msg.computeDevice: 'இந்தச் சாதனத்தில்',
  Msg.computeServer: 'சேவையகத்தில்',
  Msg.settingsPrivacy: 'தனியுரிமை',
  Msg.settingsResetId: 'என் அநாமதேய நிறுவல் குறியீட்டை மீட்டமை',
  Msg.settingsResetIdDone: 'புதிய அநாமதேயக் குறியீடு உருவாக்கப்பட்டது.',
  Msg.settingsVersion: 'பதிப்பு',
  Msg.settingsComputedOn: 'கணக்கிடப்பட்டது',
  Msg.mapAttribution:
      '© OpenStreetMap பங்களிப்பாளர்கள் (ODbL) · OpenFreeMap © OpenMapTiles',
  Msg.settingsLicences: 'மென்பொருள் உரிமங்கள்',
  Msg.settingsDataSources: 'தரவு மூலங்களும் உரிமங்களும்',
  Msg.dataSourcesBody:
      'சாலைகள் மற்றும் அடிப்படை வரைபடம்: © OpenStreetMap பங்களிப்பாளர்கள், '
      'Open Database Licence (ODbL), https://www.openstreetmap.org/copyright. '
      'அடிப்படை வரைபடத்தை OpenFreeMap, OpenMapTiles மூலம் வழங்குகிறது. இந்தச் '
      'செயலியில் உள்ள வழித்தடத் தரவு OpenStreetMap-இலிருந்து உருவாக்கப்பட்டது; '
      'அதே உரிமத்தில் பகிரப்படுகிறது.\n\n'
      '{data_credit}\n\n'
      'இந்தச் செயலி ஒப்பீட்டு அபாயத்தையும் சான்று எவ்வளவு பழையது என்பதையும் '
      'மட்டுமே காட்டுகிறது. எந்தச் சாலை பற்றியும் எந்த உறுதியும் அளிக்காது.',
  Msg.onDevice: 'இந்தச் சாதனத்தில்',
  Msg.onServer: 'சேவையகத்தில்',
  Msg.cancel: 'ரத்து',
  Msg.close: 'மூடு',
};
