---
name: "human-scope"
description: "Write or revise any prose (essays, research papers, literature reviews, reports, fiction, emails, posts, statements, speeches) so it reads as deliberately written by a careful person: specific, committed, evidence-sized, free of AI patterns. Use for Human Scope, de-AI or humanize requests, or any writing where voice matters."
---

# Human Scope

Human Scope makes writing read as the product of decisions. It does not imitate human mistakes.

Machine-generated prose is recognisable less by any single word than by **defaults**. It reaches for the safe abstraction, the balanced triplet, the summarising last line, the tidy ending and the inflated verb. Human writing that works makes choices instead: it picks a claim, a detail, a rhythm and an ending for this reader and this piece.

This skill turns that difference into checks you can run. It covers every genre, from a 300-word email to an IEEE paper.

## Source and limits

The narrative principles come from *StoryScope: Investigating idiosyncrasies in AI fiction* by Jenna Russell, Rishanth Rajendhran, Chau Minh Pham, Mohit Iyyer and John Wieting (August 2026 revision).
- Paper: https://jenna-russell.github.io/assets/pdf/storyscope.pdf
- Code: https://github.com/jenna-russell/storyscope

What the study did:
- analysed 61,608 long-form stories;
- separated human from AI fiction with 93.2% binary macro-F1 on its own task.

That figure is a classification result for that task. It is not a detector accuracy or a quality score, and its findings describe population averages. Human writing is not one style.

The pattern catalogue in Section 4 generalises those findings to non-fiction from common editorial experience. Treat it as editorial guidance, not as measured fact.

Nothing here guarantees any detector outcome or makes text human-authored. The aim is better writing.

## 1. Before writing: fix the decisions a template would otherwise make

Answer these six questions in a line each, from the brief. Ask the user only if a missing answer makes a coherent draft impossible.

1. **Reader.** Who reads this, what do they already know, and what will they do next?
2. **Point.** What is the one claim, finding, request or change of state? Write it in one sentence before drafting. If you cannot, you are not ready to draft.
3. **Mode.** Pick the mode (Section 5). It sets register, evidence rules and structure.
4. **Specifics on hand.** List the names, numbers, dates, places, quotations, examples and sources actually available.
   - Specificity must come from this list.
   - **Never invent a fact, figure, quotation, source, anecdote or person to sound concrete.** Where a specific is needed and missing, write a visible placeholder such as `[figure: 2024 enrolment]` and list it as an open item.
5. **Stance.** What do you actually think, and how sure are you? Decide where the uncertainty really lies, so hedges go only there.
6. **Ending.** What must the ending resolve, and what may it honestly leave open?

## 2. Core principles (all modes)

**P1. Specific beats general.**
- Prefer a name, number, mechanism, place or observed detail to an adjective or category.
  - Generic: "The policy had significant impacts on many communities."
  - Specific: "After the 2019 fare rise, weekday ridership on Route 21 fell by a third."
- Every paragraph of non-fiction should contain at least one checkable particular. Every scene in fiction should contain at least one detail only this story would have.
- Generic examples ("for instance, a small business owner might...") are a tell. Use a real case, or a precise hypothetical with numbers.

**P2. Commit.**
- State the claim, then qualify it where the evidence is actually weak.
- Do not balance for the sake of balance ("On one hand... on the other...") when you hold a view.
- Do not end with "ultimately, it depends" when you can say what it depends on and which way it falls.

**P3. Size every claim to its evidence.**
- Separate what was observed or measured from what is inferred or believed.
- Use one hedge, placed on the uncertain part.
  - Hedge stack: "may potentially help to somewhat reduce".
  - Placed hedge: "reduced costs in both pilots; whether this holds at scale is untested".
- Never write "first", "only", "unprecedented", "proven" or "always" without support.

**P4. Say it once, in the right place.**
- Do not announce a point ("In this section I will..."), make it, then summarise it.
- Do not restate in prose what a table, figure or the previous sentence already showed. Tell the reader what to notice.
- In fiction, do not let the narrator explain a meaning the scene already carries.

**P5. Let structure follow the content.**
- Paragraph length, sentence length and section shape should vary because the material varies, not to a template.
- A list exists because items are parallel and the reader will scan them, not to look organised.

**P6. Earn the ending.**
- Resolve what was promised. Leave open what is genuinely open, and say so where the genre allows.
- No uplift, moral or slogan the body did not earn.
- End on the last substantive thing: a consequence, a next step, an image, a decision.

**P7. Keep the writer's voice.**
- When revising, preserve the author's register, idiom, regional spelling, humour and deliberate quirks.
- Remove only what is generic. Do not homogenise a distinctive voice into "clean" prose.

## 3. Precision targets (measurable defaults)

These are defaults for English prose. Override any of them when the user's own voice, the genre or the publisher's style clearly calls for it, and note the override.

| Feature | Target |
|---|---|
| Em dashes (—) | At most 2 per 1,000 words, and never as a rhythm device to set up a reveal. Use a comma, colon, parentheses or a new sentence. |
| Triplets: three adjectives, three parallel clauses, "X, Y and Z" flourishes | At most 1 per 300 words of argument. A genuine list of three facts is fine. A rhetorical triplet is not. |
| Contrast frames: "not X but Y", "isn't X, it's Y", "less about X, more about Y" | At most 1 per piece, and only when someone actually holds X. |
| Participial tails: "..., highlighting / underscoring / reflecting / demonstrating / showcasing the importance of ..." | At most 1 per 500 words. Usually delete the tail, or make it a sentence with a real subject and evidence. |
| Paragraphs opening with a conjunctive adverb (Moreover, Furthermore, Additionally, Notably, Importantly, Ultimately) | At most 1 in 5 paragraphs. |
| Paragraphs ending in a summary or aphorism ("This shows that...", "And that makes all the difference.") | At most 1 per piece. |
| Sentence length | In any paragraph of 4 or more sentences (expository and narrative prose), lengths should visibly vary: at least one under about 10 words and one over about 25. If every sentence falls between 15 and 25 words, revise. Technical steps and instructions are exempt. |
| Rhetorical questions | 0 in academic and technical prose. At most 1 per 500 words elsewhere, and only if the next sentence does not simply answer it. |
| Bold text | Only for terms being defined, warnings, or labels in reference documents. Never for emphasis inside an argument. |
| Headings | None under about 600 words unless the format requires them. Sentence case unless the venue specifies title case. |
| Bullets | Only for parallel, scannable items. Arguments, causation and narrative go in paragraphs. |
| Synonym cycling for a key term (method → approach → technique → framework) | 0 in technical writing. Define a term once and repeat it exactly. |

## 4. AI-pattern catalogue

Work through the levels in order: document first, word last. Fixing words inside a templated structure only produces a templated structure with different words.

### 4.1 Document level
- **Prompt echo.** Opening by restating the question or topic ("Climate change is one of the most pressing issues of our time"). Fix: open with the claim, a finding, a scene or a concrete problem.
- **Throat-clearing intro.** Two or more sentences of context before the point. Fix: put the point within the first three sentences (non-fiction) or the first paragraph (fiction).
- **Mirror structure.** Every section has the same shape and length. Fix: give more space to what matters and compress the rest.
- **Summary conclusion.** The ending recaps each section in order. Fix: end with implication, consequence, decision or an honest open question.
- **Uplift or moral ending.** "The future looks bright", "only time will tell", "together we can". Fix: cut it, and end one sentence earlier.
- **Over-resolution.** Every thread is tied off and every tension relieved. Fix: resolve the central promise and let secondary threads stay as they are.
- **False balance.** Equal space given to positions the evidence does not support equally. Fix: weight space by evidence.
- **Meta-commentary.** "This essay will explore...", "As discussed above...". Fix: delete it, or replace it with the content itself.

### 4.2 Paragraph level
- **The template paragraph.** Topic sentence, three supporting points, wrap-up line. Fix: let some paragraphs be one long chain of reasoning, some a single short sentence, and some open on the evidence before the claim.
- **Uniform length.** All paragraphs at four to six sentences. Fix: let the length follow the content.
- **The "This" summariser.** Sentences beginning "This highlights / shows / underscores / demonstrates...". Fix: name the subject ("The 12% drop shows...") or delete the sentence.
- **Transition stacking.** A connective at the start of every paragraph. Fix: let the logic carry the link, and keep connectives where the relation is not obvious (however, therefore, by contrast).
- **Generic example slot.** "For example, imagine a student who...". Fix: use a real case, or a precise one with numbers and names.

### 4.3 Sentence level
- **Contrast reveal.** "It's not just X. It's Y." / "This isn't about X; it's about Y."
- **Colon or question reveal.** "The result? X." / "The best part: X." / "Here's the thing:"
- **Participial tail.** "..., underscoring the need for X."
- **Range flourish.** "From X to Y, ..." used to sound sweeping.
- **Hedge stack.** "could potentially", "may possibly", "somewhat arguably".
- **Nominalisation chain.** "the implementation of the optimisation of the allocation". Fix: "we allocated...".
- **Empty intensifier.** "truly", "incredibly", "deeply", "profoundly", "absolutely".
- **Vague attribution.** "Experts agree", "studies show", "research suggests" with no source. Fix: name the source or drop the claim.
- **Second person in the wrong register.** "you" in academic prose, or "Whether you're a student or a professional...".

### 4.4 Word level
These words are not banned. They are flagged when they are filler: when a plainer or more specific word would carry more meaning. Replace them unless the word is exactly right and the user would naturally use it.
- **Verbs:**
  - delve, leverage, utilise/utilize, harness, unlock, unleash, foster, bolster, empower, elevate, streamline;
  - underscore, showcase, spotlight, navigate (figurative), embark, resonate, align (figurative), revolutionise.
- **Adjectives:**
  - crucial, pivotal, vital, paramount, robust (unless defined), seamless, intricate, multifaceted;
  - nuanced (as filler), comprehensive (as filler), dynamic, vibrant, bustling, ever-evolving, cutting-edge, state-of-the-art (as filler);
  - transformative, groundbreaking, game-changing, invaluable, commendable, meticulous, profound.
- **Nouns:**
  - landscape, realm, tapestry, testament, beacon, symphony, journey (figurative), synergy, paradigm (as filler);
  - the power of, a myriad of, a plethora of.
- **Stock phrases:**
  - it's important / worth noting, in today's fast-paced / digital world, when it comes to;
  - plays a crucial / vital / pivotal role, a testament to, serves as a reminder, stands as;
  - shed light on, pave the way, at its core, in the realm of, let's dive in, in conclusion, in summary, ultimately;
  - only time will tell, the future looks bright.
- **Assistant register (never in a deliverable):** certainly, great question, I hope this helps, feel free to, happy to help, as an AI.

### 4.5 Formatting level
- Bolded "Term: explanation" bullet lists standing in for prose.
- Headings on short pieces.
- Emoji as section markers.
- Tables for things that are not comparisons.
- Checkmark or arrow glyphs in formal prose.

## 5. Modes

### 5.1 Essays (argumentative, analytical, personal, academic coursework)
- **Thesis.** The thesis is a claim someone could dispute, stated by the end of the first paragraph. "This essay will discuss X" is not a thesis.
- **Counterargument.** Address the strongest one, named concretely. Then concede what is true and show why the thesis survives. Do not rebut a straw version.
- **Body paragraphs.** Each one advances the argument, so the reader could not reorder them without losing something.
- **Personal essays:** one scene told in full beats five events summarised.
  - Show the moment, not the lesson.
  - Do not end with "This experience taught me...". Let the last image or action carry the change.
- **Conclusion.** Extend the argument (consequence, limit, next question). Do not repeat the thesis in new words.

### 5.2 Research papers, literature reviews, theses
- **Contributions** are narrow and honest. Write "we are not aware of work that..." plus the search scope, not "novel" or "first".
- **Report numbers** with uncertainty and n. An interval that includes zero is inconclusive. Report null and negative results plainly, in the abstract if they are the main finding.
- **Measured vs inferred.** Keep them apart in the same sentence: "rose by 0.14 [0.11, 0.18]; this is consistent with, but does not show, ...".
- **Other people's work.** Describe it only as far as you have read it. Paraphrase in your own sentence structure: read the source, close it, then write. Run a six-word overlap check against source abstracts and rewrite hits that are not quotes, titles or standard terms.
- **Reasons for choices.** Explain them: "We used 100 pairs because each call reloads the graph (3 s)." Admit corrections to earlier versions when they change conclusions.
- **Literature reviews:**
  - organise by question or capability, not by paper;
  - end each subsection with what remains open, grounded in the works just cited;
  - group citations only when the works make the same point;
  - state the search method and its limits.
- **Tense and person.** Use "we" for what the authors did, past tense for experiments, present tense for what the paper shows.
- **Other skills.** Defer to `ieee-research-paper` (or the venue's style guide) for citations, references and format. This skill governs voice and claim-sizing.

### 5.3 Reports, proposals, business and technical documents
- Put the conclusion or recommendation first, then the evidence.
- Each recommendation names an owner, an action and a date or trigger.
- Prefer numbers with units and comparisons ("Rs 4.2 lakh, 18% above the 2025 quote") to qualitative labels ("significant cost").
- Use the same term for the same thing throughout. Define acronyms once.
- Cut the "Executive summary" if the document is under two pages: the first paragraph is the summary.

### 5.4 Fiction (StoryScope-derived)
Treat these as editorial questions, not a formula. Pick the few that apply.
- **Let tension accumulate.** A conflict should change what someone can lose, choose or understand. Do not smooth away an obstacle right after introducing it. Quiet stories can build tension through withheld information, social pressure or contradictory desires.
- **Keep subtext available.** Let action, chosen detail and dialogue carry meaning. Flag narration that restates what the scene already shows. Keep explicit reflection where voice, accessibility or genre calls for it.
- **Earn resolution.** Resolve the central promise. Ask whether every secondary thread needs a bow. Ambiguity should have consequences, not be random incompleteness.
- **Permit purposeful digression.** A detour should reveal character, complicate causality or change later interpretation.
- **Vary voice.** Characters have distinct knowledge, motives and speech. No character is a mouthpiece for the theme.
- **Choose settings for the story.** Do not default to bleak or ruined environments. An ordinary or bright setting can carry conflict.
- **Use gossip only when it changes something.** Social information should alter relationships, stakes or choices, not deliver convenient exposition.
- **Let surprises recontextualise.** A reveal should change the meaning of an earlier detail, not just startle.
- **Use time structure intentionally.** Linear is valid. Use flashback, omission or non-linearity only when it improves understanding, suspense or perspective.
- **Ground references in the story's world and voice.** Never invent real-world quotations or evidence.

### 5.5 Short-form: emails, messages, posts, cover letters, statements of purpose
- **First line.** It carries the request or the news. No "I hope this email finds you well" unless the user writes that way.
- **Length.** One idea per message where possible. Cut the closing paragraph that repeats the request.
- **Cover letters and statements.** Replace every trait claim ("passionate", "hard-working", "detail-oriented") with one specific thing the person did and its result. Name the programme, lab, person or product you are writing to, and say why that one.
- **Social posts.** No hook formulas ("Here's what nobody tells you", "Let that sink in"), no one-line-per-paragraph staircases, no closing question posted only for engagement.

### 5.6 Speeches, talks and scripts
- Write for the ear:
  - shorter sentences;
  - deliberate repetition of the key phrase (allowed here);
  - concrete images;
  - numbers rounded to what a listener can hold.
- Earn rhetorical devices: one strong triplet beats five weak ones, and the triplet limit still applies outside the climax.
- Open with a person, a moment or a number, not with "Good morning, today I'm going to talk about".

## 6. Workflow

**Drafting**
1. Answer the six questions in Section 1.
2. Draft the point sentence, the order of claims or scenes, and the ending first.
3. Write the body from the specifics list. Leave placeholders rather than inventing.

**Revising (yours or the user's text)**
1. Read the whole text before changing anything.
2. Mark the three highest-impact problems, at document or paragraph level. For each, note a short excerpt and the effect of the fix.
3. Revise in this order: structure, then paragraphs, then sentences, then words.
4. Run the audit in Section 7 and fix what it finds.
5. Check continuity, chronology, numbers, names and cause-and-effect. In fiction, also check who knows what when.
6. Return the text in the requested form:
   - if only prose was requested, return only prose;
   - if a review was requested, add a short list of the changes and any intentionally open questions;
   - list any placeholders or unverified facts as open items.

## 7. Audit (run before delivering)

Run this on the final text when a shell is available. Otherwise apply it by hand.

```python
import re, statistics, sys
t = open(sys.argv[1], encoding='utf-8').read()
w = len(re.findall(r"\b\w+\b", t)) or 1
per_k = lambda n: round(1000 * n / w, 1)
flags = r"\b(delve|leverag\w*|utili[sz]\w*|harness\w*|unlock\w*|foster\w*|bolster\w*|empower\w*|elevat\w*|streamlin\w*|underscor\w*|showcas\w*|navigat\w*|embark\w*|resonat\w*|crucial|pivotal|vital|paramount|robust|seamless\w*|intricate|multifaceted|transformative|groundbreaking|invaluable|meticulous\w*|profound\w*|landscape|realm|tapestry|testament|beacon|synergy|myriad|plethora)\b"
phr = r"(it'?s (important|worth) (to note|noting)|in today'?s|when it comes to|plays? a (crucial|vital|pivotal|key) role|shed light|pave the way|at its core|in the realm of|in conclusion|in summary|only time will tell|let'?s dive)"
sents = [s for s in re.split(r"(?<=[.!?])\s+", t) if len(s.split()) > 2]
lens = [len(s.split()) for s in sents]
paras = [p for p in t.split('\n\n') if p.strip()]
print('words', w)
print('em dashes per 1k', per_k(t.count('—')))
print('flag words', sorted(set(m.lower() for m in re.findall(flags, t, re.I))))
print('stock phrases', len(re.findall(phr, t, re.I)))
print('contrast frames', len(re.findall(r"\b(not (just|only|merely) [^.]{1,60}(but|it'?s)|isn'?t (about )?[^.]{1,40}[;,.] it'?s)", t, re.I)))
print('participial tails', len(re.findall(r",\s+(highlighting|underscoring|reflecting|demonstrating|showcasing|emphasi[sz]ing|illustrating|signaling|signalling)\b", t, re.I)))
print('para openers (adverbs)', sum(bool(re.match(r"\s*(Moreover|Furthermore|Additionally|Notably|Importantly|Ultimately|Overall)\b", p)) for p in paras), 'of', len(paras))
print('"This" summarisers', len(re.findall(r"(?:^|[.!?]\s+)This (shows|highlights|underscores|demonstrates|illustrates|suggests|means)\b", t)))
print('rhetorical questions', t.count('?'))
if len(lens) > 3: print('sentence length mean/sd', round(statistics.mean(lens), 1), round(statistics.pstdev(lens), 1))
```

Read the output against Section 3. The tool can only find candidates; a person decides.
- **Sentence-length spread.** A standard deviation below about 6 words in expository prose usually means the rhythm is too uniform.
- **Flag words.** Each one needs a reason to stay.

Then check by eye what a script cannot:
- Is the point visible early?
- Does every paragraph contain a particular?
- Is any point made twice?
- Does the ending add something?
- Does every claim have the support its wording implies?
- Is any fact, figure, quotation or source invented? (Must be none.)

## 8. Do not

- **Imitate humans.** Do not add typos, awkward grammar, random digressions, slang or gratuitous ambiguity to seem human.
- **Invent.** Do not invent specifics, anecdotes, quotations, data or citations to satisfy P1. Use placeholders.
- **Over-correct.** Do not ban em dashes, particular words, clean structure or happy endings categorically. The targets are densities and defaults, and the user's own voice overrides them.
- **Strip needed help.** Do not remove explanations, definitions or signposting the reader actually needs (instructions, accessibility, legal or safety text).
- **Erase voice.** Do not flatten a distinctive author voice into neutral prose.
- **Over-claim the method.** Do not infer authorship from a passage, or promise that a detector will classify the result a certain way.
- **Replace judgement.** Do not let statistical averages (StoryScope's or this checklist's) override the user's creative or scholarly judgement.