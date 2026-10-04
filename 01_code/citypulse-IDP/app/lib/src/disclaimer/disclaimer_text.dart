/// `docs/DECISIONS.md` ADR-011's mandatory disclaimer text. Verbatim --
/// do not paraphrase the long form; ADR-011 specifies it word for word and
/// `DisclaimerGate` enforces it as a gate, not a dismissible hint.
library;

/// The unavoidable first-use (and per-app-version) disclaimer. ADR-011:
/// "Before first use, and once per app version thereafter, the app shows an
/// unavoidable disclaimer" -- this exact sentence.
const String kFirstUseDisclaimer =
    'CityPulse is a research prototype. It estimates risk from limited '
    'data — it does not guarantee any road is safe. Always use your own '
    'judgement.';

/// ADR-011: "A shorter form of the same sentence repeats on any card whose
/// `confidence_band` is `low` or `stale`." No exact wording is specified
/// there -- this is a deliberately short paraphrase that keeps the same two
/// hedges (limited data, not a guarantee) without repeating the full
/// disclaimer on every low/stale card.
const String kRepeatDisclaimer =
    'Reminder: estimated from limited data, not a safety guarantee. Use '
    'your own judgement.';
