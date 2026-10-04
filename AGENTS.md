# AGENTS.md

This file is for any AI agent: Codex, Cursor, Gemini, Copilot, Jules, Windsurf, Claude and others.

1. **Read `CLAUDE.md` in this folder completely before anything else.** It is the authoritative brief. It overrides `01_code/citypulse-IDP/CLAUDE.md`, the README badges and the pitch documents.
2. **Then read, in order:**
   1. `00_START_HERE/PROJECT_STATUS.md`
   2. `00_START_HERE/KNOWN_FLAWS.md`
   3. `00_START_HERE/NEXT_STEPS.md`
   4. `PLAN.md` (the build plan: pick tasks by the rules in its Section 1)
3. **Follow the safety rules in `CLAUDE.md` §2:**
   - work only inside this folder;
   - never delete without approval;
   - never overwrite pinned data;
   - never fabricate numbers or citations;
   - use the claims wording table in §6.
4. **Follow the task protocol in `CLAUDE.md` §9.** In short:
   - run the tests first;
   - make a small change with a test;
   - write results to new dated folders;
   - record findings in the flaw register.

Role briefs for specific jobs (implementer, reviewer, experimentalist, paper-writer, data-wrangler) are in `01_code/citypulse-IDP/.claude/agents/`. Where they conflict with `CLAUDE.md`, `CLAUDE.md` wins.
