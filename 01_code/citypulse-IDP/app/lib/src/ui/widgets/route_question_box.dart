/// "Ask about this route" (ADR-035): a box where the traveller types a question and gets an answer drawn from
/// this route's own [DecisionTrace], on the phone, with no network and no language model.
///
/// The answer comes from `pulse_explain`'s `answerQuestion` (D0): a fixed classifier and fixed English and
/// Tamil templates, passed through the verifier. **ADR-011 holds here as everywhere:** a question that asks
/// whether a road is safe, dry or open is answered with what CityPulse cannot confirm and what the data
/// shows, never with a verdict. Nothing typed is stored, logged or sent anywhere; the box forgets the
/// exchange when the route changes (the caller keys it by the trace's query id).
///
/// The answer is in Tamil when the question contains Tamil script, otherwise in English, whatever the
/// app's language: the answer follows the language the traveller wrote in. The example questions follow
/// the app's language.
///
/// The Tamil wording of the answers has not been reviewed by a native speaker (KNOWN_FLAWS F-43).
library;

import 'package:citypulse_app/src/core/strings.dart';
import 'package:citypulse_app/src/disclaimer/disclaimer_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

/// The longest question accepted, in characters.
const int kMaxQuestionLength = 200;

/// The question box for one route.
class RouteQuestionBox extends StatefulWidget {
  /// Creates the box. [trace] and [eventState] are the route's own; [hazardNouns] is the `display_noun`
  /// vocabulary the verifier needs.
  const RouteQuestionBox({
    required this.trace,
    required this.eventState,
    required this.hazardNouns,
    required this.strings,
    this.labeler,
    super.key,
  });

  /// The route's decision trace: the only source of facts.
  final DecisionTrace trace;

  /// The flood-event state the route was calculated under.
  final EventState eventState;

  /// Hazard class to display noun.
  final Map<String, String> hazardNouns;

  /// The text source.
  final Strings strings;

  /// The on-device model that labels the question (D1), or `null` to answer with the rule-based answerer alone.
  final QuestionLabeler? labeler;

  @override
  State<RouteQuestionBox> createState() => _RouteQuestionBoxState();
}

class _RouteQuestionBoxState extends State<RouteQuestionBox> {
  final _controller = TextEditingController();
  QaAnswer? _answer;
  var _copied = false;

  @override
  void initState() {
    super.initState();
    // Rebuild as the text changes so the clear button appears only when there is something to clear.
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  var _busy = false;
  var _ticket = 0;

  Future<void> _ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _busy) return;
    QaAnswer? answer;
    if (widget.labeler == null) {
      // No model: the rule-based answer, immediately and in the same frame, exactly as before.
      try {
        answer = answerQuestion(
          question: q,
          trace: widget.trace,
          eventState: widget.eventState,
          hazardDisplayNouns: widget.hazardNouns,
        );
      } on Object {
        // Never leave the traveller with an error screen: show the fixed fallback.
        answer = null;
      }
    } else {
      final ticket = ++_ticket;
      setState(() => _busy = true);
      try {
        answer = (await answerWithLabeler(
          question: q,
          trace: widget.trace,
          eventState: widget.eventState,
          hazardDisplayNouns: widget.hazardNouns,
          labeler: widget.labeler,
        )).answer;
      } on Object {
        answer = null;
      }
      if (!mounted || ticket != _ticket) return;
    }
    setState(() {
      _busy = false;
      _answer = answer;
      _fallbackLocale = detectLocale(q);
      _failed = answer == null;
      _copied = false;
    });
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = true);
  }

  var _failed = false;
  var _fallbackLocale = 'en';

  List<String> get _examples {
    final s = widget.strings;
    return [
      s(Msg.askExample1),
      s(Msg.askExample2),
      s(Msg.askExample3),
      s(Msg.askExample4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final text = Theme.of(context).textTheme;
    final band = widget.trace.confidenceBand;
    final needsRepeat =
        band == ConfidenceBand.low || band == ConfidenceBand.stale;
    final shown = _failed
        ? (_fallbackLocale == 'ta' ? kQaFallbackTa : kQaFallbackEn)
        : _answer?.text;
    final headline = _failed ? '' : (_answer?.headline ?? '');
    final head = shown != null && headline.isNotEmpty && shown.startsWith(headline)
        ? headline
        : '';
    final rest = shown == null ? '' : shown.substring(head.length);
    final follow = _failed ? const <QaIntent>[] : (_answer?.followUps ?? const <QaIntent>[]);
    final answerTamil = _failed ? _fallbackLocale == 'ta' : (_answer?.locale == 'ta');

    return Column(
      key: const Key('ask-box'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(s(Msg.askHeading), style: text.titleSmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('ask-field'),
                controller: _controller,
                maxLength: kMaxQuestionLength,
                maxLines: 1,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kMaxQuestionLength),
                ],
                textInputAction: TextInputAction.send,
                onSubmitted: _ask,
                scrollPadding: const EdgeInsets.only(bottom: 160),
                decoration: InputDecoration(
                  hintText: s(Msg.askHint),
                  isDense: true,
                  counterText: '',
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('ask-clear'),
                          icon: const Icon(Icons.close),
                          tooltip: s(Msg.askClear),
                          onPressed: _controller.clear,
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('ask-send'),
              onPressed: _busy ? null : () => _ask(_controller.text),
              child: Text(s(Msg.askSend)),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label: s(Msg.askThinking),
            child: Column(
              key: const Key('ask-thinking'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(s(Msg.askThinking), style: text.bodySmall),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var i = 0; i < _examples.length; i++)
              ActionChip(
                key: Key('ask-chip-$i'),
                label: Text(_examples[i]),
                onPressed: () {
                  _controller.text = _examples[i];
                  _ask(_examples[i]);
                },
              ),
          ],
        ),
        if (shown != null) ...[
          const SizedBox(height: 8),
          Card(
            key: const Key('ask-answer-card'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          // The first sentence is the direct answer; the rest is the detail.
                          if (head.isNotEmpty)
                            TextSpan(
                              text: head,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          TextSpan(text: rest),
                        ],
                      ),
                      key: const Key('ask-answer'),
                      style: text.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s(Msg.askSource),
                    key: const Key('ask-source'),
                    style: text.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('ask-copy'),
                      onPressed: () => _copy(shown),
                      icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                      label: Text(s(_copied ? Msg.askCopied : Msg.askCopy)),
                    ),
                  ),
                  if (needsRepeat) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Text(
                      kRepeatDisclaimer,
                      key: const Key('ask-repeat-disclaimer'),
                      style: text.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (follow.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < follow.length; i++)
                  ActionChip(
                    key: Key('ask-followup-$i'),
                    label: Text(canonicalQuestion(follow[i], ta: answerTamil)),
                    onPressed: () {
                      final q = canonicalQuestion(follow[i], ta: answerTamil);
                      _controller.text = q;
                      _ask(q);
                    },
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
