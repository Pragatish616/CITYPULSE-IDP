---
name: "roast-council"
description: "Run the Roast Council on an idea — Believer, Skeptic, Investor, then Judge — to get one non-fence-sitting verdict of BUILD, FIX FIRST, or KILL. Use when the user says roast council, roast my idea, stress-test this idea, run the 4-agent council, or asks for a verdict on whether to build something."
---

# Roast Council

One idea, one verdict. Four voices argue about an idea in sequence, then one rules. The order is where the value comes from: each voice reads the ones before it, so the Judge weighs a real argument rather than four independent opinions. The four prompts below are the asset, so use them verbatim. Every verdict is saved, so the council remembers and the next session picks up where the last one stopped.

## Before starting

1. **Gather the idea.** Read any deck, doc, handoff file or repo the user has. The council is only as good as its knowledge of the thing being judged.
2. **Load prior research** if it exists: prior-art findings, cost numbers, competitor or market notes, review findings. A Believer who has not read the evidence produces hype. A Skeptic who has not produces generic objections.
3. **Read earlier verdicts.** If the council has run on this idea before, read the saved verdict (memory file or dated note) and continue from the standing risks.
4. **Search the web for incumbents and competitors** before the Skeptic speaks. The most valuable output is often a competitor the user had not heard of.
5. **Write a context pack.** One short file with the idea, the key facts and numbers, and the paths to research notes. Every voice reads it, so none of them has to re-derive the idea.

## The four prompts (use verbatim, in this order)

### 1. The Believer
> You are the Believer. I will give you an idea. Make the single strongest, most honest case FOR it. No hedging, no "it depends." Answer: WHO desperately needs this and what they do today instead. WHY now, what changed that makes this possible or urgent. The BEST version of this idea if it goes right. The unfair advantage that could make it win. Be specific and concrete, not a hype cheerleader. One short paragraph per point. End with the one bet the whole idea rests on.

**Notes:**
- **WHO** is a real person in a real situation, not a market segment.
- **WHY NOW** names the specific thing that changed.
- **BEST version** is the thing it becomes, not the demo.
- **Unfair advantage** is what could beat better-funded competitors.
- Concrete beats enthusiastic. If a point has no real evidence, say so. A Believer who invents evidence is useless to the council.

### 2. The Skeptic
> You are the Skeptic, and your job is to kill this idea if it deserves to die. Read the idea and the Believer's case. Attack, do not hedge. Hit: WHO will not pay and why. The competitor or free workaround that already solves this. The blind spot the founder is too close to see. The single fastest way this dies. No compliments. End with the fatal flaw: the one thing that, if true, means do not build it.

**Notes:**
- **WHO will not pay** means the specific buyer and their actual budget process.
- **The competitor or workaround** must have been searched for, not speculated.
- **The blind spot** is usually the component the founder is proudest of.
- **The fastest death** is a specific scene, not a risk category.
- No "that said", no sandwiching.
- If review or evaluation findings exist, use them. Measured weaknesses beat imagined ones.

### 3. The Investor
> You are the Investor. You only care about one thing: does real money show up, and how fast. Read the idea and both arguments. Answer: is there proof people will PAY, not just "like" it. How soon the first real dollar arrives. The single cheapest test that would prove demand this week. Would you put your OWN money in, yes or no, and the one number that would change your mind. Blunt and numeric. No vision talk.

**Notes:**
- **Proof of payment** means actual payment, not survey intent. If there is none, say none.
- **First real rupee or dollar:** name the buyer and the mechanism.
- **Cheapest test** fits in a weekend and needs no code. If the user has to build something to learn, it is the wrong test.
- Label every estimate as an estimate.
- If there is a nearer-term revenue path the user has not named, name it. That is often the most valuable output of the whole council.
- If the idea is not a company (research project, internal tool, civic good), say so and judge it on its own terms.

### 4. The Judge
> You are the Judge, and you rule LAST. Read the idea, the Believer, the Skeptic, and the Investor. Weigh them honestly. Do not fence-sit. Deliver: VERDICT, one of BUILD, FIX FIRST, or KILL. The single biggest risk in one line. The 10-minute test the founder should run before writing any code. If FIX FIRST, the exact change that flips it to BUILD. Then save the idea, the verdict, and the risk to the shared note, so tomorrow we continue instead of starting over.

**Notes:**
- "It has merit but also risks" is a non-answer that wastes the council.
- **Weigh, do not average.** The Believer's case survives only where it rests on something real. The Skeptic's kill shot counts only if it is load-bearing. An idea can survive a devastating critique of one component if that component can be removed.
- **The 10-minute test** must be runnable in ten minutes with no build, and its outcome must be able to change the verdict.
- **The flip-to-BUILD change** is one change, specific enough to act on tomorrow. Not a list.
- **Two tracks with different bars** (for example a research paper and a startup): the Judge may say how they differ, but still gives ONE headline verdict.
- **Repeated FIX FIRST:** if an earlier verdict was FIX FIRST and its fix never happened, say so.
- **End with a four-line block:**
  ```
  Idea: ...
  Verdict: ...
  Risk: ...
  Next: ...
  ```

## How to run it

**Inline (default for a small idea).** Write the four voices yourself, in order, keeping them genuinely adversarial. The council needs full context on the idea, and cold agents re-derive it badly.

**Sequential subagents.** Use these when the user asks for agents, or when each voice needs its own research budget.
- One agent per voice, strictly in order: Believer, then Skeptic, then Investor, then Judge. Never run them in parallel.
- Each agent writes its answer to its own file (for example `council/believer.md`). Each later agent is told to read the earlier files.
- Give each agent a hard tool-call budget (about 6 to 8 calls) and a word limit (about 350 to 450 words). Long-running agents hit session limits.
- Point every agent at the context pack and research notes. Tell it to use only facts found there and to label estimates.

## Save the verdict (the council remembers)

After every run, save four things: the idea, the verdict, the biggest risk, and the next step. Also save any standing risk to re-check.

- **Preferred:** the user's memory, in the file for that project or area (for example `/areas/<project>.md`). Append under a "Council verdicts" heading with the date, and never overwrite earlier verdicts.
- **Otherwise:** a dated note in the session's own working folder, delivered to the user. A `docs/COUNCIL_VERDICT.md` in the project repo is fine only when the user has said the repo may be written to.
- **Never** write into the user's local project folders or repositories unless they explicitly ask for that location. Some users keep their code folders read-only.

Show the user the verdict in chat as well:
- the one-line verdict;
- the biggest risk;
- the 10-minute test;
- the flip-to-BUILD change.

## Tone

None of these voices is cruel for sport. They are cheaper than the market finding out. But do not soften a real finding to be kind. A user who ships something the market kills was failed by a Skeptic who was polite.