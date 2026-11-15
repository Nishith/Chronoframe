# NAS v1 orchestrator kickoff

## Before you start (owner, once)

Run these from the repo root. They install the plan's subagents and project permissions into `.claude/`. The copy of `settings.json` refuses to overwrite an existing file.

```bash
mkdir -p .claude/agents
```

```bash
cp docs/plan/nas-v1/claude-config/agents/nas-*.md .claude/agents/
```

```bash
cp -n docs/plan/nas-v1/claude-config/settings.json .claude/settings.json
```

Then open Claude Code on this Mac in `/Users/nishithnand/Code/Chronoframe`, choose Opus as the model, set the permission mode to accept edits (or auto), and paste the prompt below.

## Kickoff prompt

```text
You are the orchestrator for Chronoframe NAS v1. Work unattended until the plan is finished or every remaining item is blocked. Do not ask me questions.

1. Read, in order: docs/plan/nas-v1/NAS_AGENT_RULES.md, docs/plan/nas-v1/IMPLEMENTATION_PLAN.md, docs/plan/nas-v1/CONTRACTS.md, docs/plan/nas-v1/DECISIONS.md, docs/plan/nas-v1/PROGRESS.md, docs/plan/nas-v1/BLOCKED.md, docs/plan/nas-v1/ACCEPTANCE_MATRIX.md. The requirements are docs/NAS_REQUIREMENTS.md (approved v1.0); only its P0 v1 scope is in play.
2. Do WP-00 yourself, exactly as written.
3. Then run the work packages strictly in the plan's run order, one at a time (SwiftPM shares one build directory). For each WP:
   a. Mark it in-progress in PROGRESS.md.
   b. Brief the nas-implementer subagent with: the WP ID, its owned paths, the contract and decision IDs it cites, its acceptance test names, and its Done-when commands. Tell it to read NAS_AGENT_RULES.md first.
   c. When it reports, brief the nas-reviewer subagent on the same WP. If the reviewer says "changes required", send the blocking findings back to the same implementer (continue it, don't start a new one), then review again. Two failed review rounds → log BLOCKED.md and move on.
   d. For WP-06 and WP-07, also read the full diff of TransferExecutor.swift, OrganizerDatabase.swift and DestinationOperationLock.swift yourself and confirm every changed line traces to C-08, C-09 or C-10. Record that review in PROGRESS.md.
   e. Run the WP's Done-when commands yourself. Record each command and exit code in PROGRESS.md.
   f. Log any ambiguity the implementer resolved as D-NAS-1NN in DECISIONS.md.
   g. Commit only that WP's owned paths plus the plan files you updated: git add <explicit paths>; git commit -m "NAS <WP-ID>: <title>". Never git add -A or git add .
   h. Use the nas-data-entry subagent for acceptance-matrix and ledger row updates.
4. Run gates G2 and G3 yourself exactly as written.
5. Keep PROGRESS.md current after every step. After any context compaction, re-read NAS_AGENT_RULES.md, PROGRESS.md and BLOCKED.md before doing anything else, and continue from the first WP that is not done.
6. Stop only when: G3 is done; or every remaining WP depends on an open BLOCKED.md item; or WP-00 step 2 cannot switch branches. Never push, never open a pull request, never touch untracked files you didn't create, never mark a hardware row as passed.
7. Finish with a final message that has: commits made (hash and title), each gate's commands with exit codes, per slice "compiled", "tested" and "verified" status reported separately, open BLOCKED.md items with your recommendation, and the hardware checklist H1–H8 I need to run, with the exact commands from EVIDENCE_LEDGER.md.
```

## Resume prompt

```text
You are resuming as the orchestrator for Chronoframe NAS v1. Do not ask me questions.
Read docs/plan/nas-v1/NAS_AGENT_RULES.md, docs/plan/nas-v1/PROGRESS.md and docs/plan/nas-v1/BLOCKED.md first, then the plan, contracts and decisions sections for the next WP.
Run `git status` and `git log --oneline -15` and reconcile them with PROGRESS.md: a WP whose commit exists is done; a WP marked in-progress without a commit restarts from its acceptance tests (keep any files already in its owned paths and let the implementer continue from them).
Resolved BLOCKED.md items (I will mark them "resolved") unblock their WPs.
Then continue the kickoff procedure from step 3 with the first WP that is not done, through G3, and finish with the same final report.
```
