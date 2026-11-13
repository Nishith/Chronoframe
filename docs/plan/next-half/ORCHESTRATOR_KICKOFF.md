# Next-half orchestrator kickoff

One kickoff prompt serves every plan folder. Replace `<PLAN_DIR>` with the folder (for example `docs/plan/dedupe-persistence`) and `<BRANCH>` with the branch its `DECISIONS.md` D-01 names. Run the plans in the order `docs/plan/next-half/README.md` gives. One plan at a time; never two orchestrators in one checkout.

## Before you start (owner, once per plan)

1. The previous plan's branch is merged to `main` (or you have decided to stack; then edit that plan's D-01 first).
2. `git status` shows no modified tracked files. Untracked marketing/draft files are fine.
3. `cp docs/plan/next-half/claude-config/agents/cf-*.md .claude/agents/` and make sure `.claude/settings.json` contains the entries in `docs/plan/next-half/claude-config/settings.json`.
4. Open Claude Code in `/Users/nishithnand/Code/Chronoframe`, choose Opus, set the permission mode to accept edits (or auto), and paste the kickoff prompt below with the placeholders filled in.

## Kickoff prompt

```text
You are the orchestrator for the Chronoframe plan in <PLAN_DIR>. Work unattended until the plan is finished or every remaining item is blocked. Do not ask me questions.

1. Read, in order: docs/plan/next-half/AGENT_RULES.md, <PLAN_DIR>/IMPLEMENTATION_PLAN.md, <PLAN_DIR>/CONTRACTS.md, <PLAN_DIR>/DECISIONS.md, <PLAN_DIR>/PROGRESS.md, <PLAN_DIR>/BLOCKED.md, <PLAN_DIR>/ACCEPTANCE_MATRIX.md. The product rationale is docs/next-half-product-review-2026-11-07.md "Round 3"; only this plan's scope is in play.
2. Do WP-00 yourself, exactly as written (branch, baseline build, baseline suite).
3. Then run the work packages strictly in the plan's run order, one at a time (SwiftPM shares one build directory). For each WP:
   a. Mark it in-progress in PROGRESS.md.
   b. Brief the cf-implementer subagent with: PLAN_DIR, the WP ID, its owned paths, the contract and decision IDs it cites, its acceptance test names, and its Done-when commands. Tell it to read docs/plan/next-half/AGENT_RULES.md first.
   c. When it reports, brief the cf-reviewer subagent on the same PLAN_DIR and WP. If the reviewer says "changes required", send the blocking findings back to the same implementer (continue it, don't start a new one), then review again. Two failed review rounds → log BLOCKED.md and move on.
   d. For any WP the plan marks safety-critical, also read the full diff of the named safety-critical files yourself and confirm every changed line traces to a contract item. Record that review in PROGRESS.md.
   e. Run the WP's Done-when commands yourself. Record each command and exit code in PROGRESS.md.
   f. Log any ambiguity the implementer resolved as a runtime decision (D-<PLAN>-1NN) in DECISIONS.md.
   g. Commit only that WP's owned paths plus the plan files you updated: git add <explicit paths>; git commit -m "<PLAN PREFIX> <WP-ID>: <title>". Never git add -A or git add .
   h. Use the cf-data-entry subagent for acceptance-matrix and ledger row updates.
4. Run the plan's gates yourself exactly as written.
5. Keep PROGRESS.md current after every step. After any context compaction, re-read docs/plan/next-half/AGENT_RULES.md, <PLAN_DIR>/PROGRESS.md and <PLAN_DIR>/BLOCKED.md before doing anything else, and continue from the first WP that is not done.
6. Stop only when: the final gate is done; or every remaining WP depends on an open BLOCKED.md item; or WP-00 cannot create or switch to <BRANCH>. Never push, never open a pull request, never touch untracked files you didn't create, never mark a hardware row as passed, never edit StoreKit, purchase, or any *Capability.isEnabled release value.
7. Finish with a final message that has: commits made (hash and title), each gate's commands with exit codes, per WP "compiled", "tested" and "verified" status reported separately, open BLOCKED.md items with your recommendation, and the owner checklist from <PLAN_DIR>/EVIDENCE_LEDGER.md with its exact commands.
```

## Resume prompt

```text
You are resuming as the orchestrator for the Chronoframe plan in <PLAN_DIR>. Do not ask me questions.
Read docs/plan/next-half/AGENT_RULES.md, <PLAN_DIR>/PROGRESS.md and <PLAN_DIR>/BLOCKED.md first, then the plan, contracts and decisions sections for the next WP.
Run `git status` and `git log --oneline -15` and reconcile them with PROGRESS.md: a WP whose commit exists is done; a WP marked in-progress without a commit restarts from its acceptance tests (keep any files already in its owned paths and let the implementer continue from them).
Resolved BLOCKED.md items (I will mark them "resolved") unblock their WPs.
Then continue the kickoff procedure from step 3 with the first WP that is not done, through the final gate, and finish with the same final report.
```
