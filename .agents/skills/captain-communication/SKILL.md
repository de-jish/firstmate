---
name: captain-communication
description: >-
  Agent-only vocabulary for translating internal firstmate state into captain-facing outcomes.
  Load when composing a captain-facing message that must relay worker reports, status lines, tool output, validation labels, or decision records, or whenever you are unsure whether a term is internal jargon.
user-invocable: false
metadata:
  internal: true
---

# captain-communication

`AGENTS.md` section 9 owns the always-loaded rules: talk in outcomes, never relay raw evidence verbatim, put a captain decision as a structured question, and the escalation triggers.
This skill owns the full translation vocabulary, which is lookup material rather than something to carry every turn.

## The rule this serves

Every captain-facing message must translate internal state into the project outcome, the consequence, and the next decision.
Use the captain's nouns: the investigation, the scout, the fix, the PR, the review, the decision, the blocker, the credential, the local copy, the worker, or the project.
Scout and second mate are accepted Firstmate house vocabulary and need no translation when they naturally name that work or role.

## Internal terms that must never appear in captain chat

Startup machinery, locks, watchers, polling, crewmates, task ids, briefs, worktrees, checkouts, status or metadata files, teardown, promotion, harness names, runtime backend names, context budgets, delivery-mode names, autonomy flags, wake types, status prefixes, decision holds, pipeline step names, validation-state labels, and compressed safety labels such as fail-closed, fails closed, fail-open, fails open, fail loudly, or close variants.

## Translation table

When evidence uses an internal label, rewrite it before sending:

- worktree, checkout, primary checkout, or local-main -> local copy, isolated copy, or local branch, only if the location matters.
- teardown -> cleanup.
- wake, watcher, heartbeat, stale, signal, or check -> notification, monitoring, waiting too long, or stopped responding.
- hold, gate, ask-user, needs-decision, blocked, or paused -> the concrete decision, wait, approval, blocker, or external delay.
- done, failed, fix-review, checks-passed, cancelled, validation step, or pipeline state -> the concrete result, review finding, passing checks, failed check, or stopped validation.
- brief -> instructions.
- crewmate -> worker, only when naming the helper matters.
- harness, backend, runtime, or adapter -> worker runtime or tool, only when the tool choice itself blocks work.
- status file, metadata, state, task id, or raw path -> durable record, local record, or omit it unless the captain needs the file path to act.
- fail-closed, fails closed, fail loudly, or refuses loudly -> stops safely when something goes wrong, refuses rather than proceeding, or reports the concrete missing requirement.
- fail-open, fails open, passive fail-open, or degraded-open -> steps aside and lets work continue when the check cannot complete, or continues without that optional protection.

## Applies to chat only

Private evidence reports may retain exact identifiers, paths, status lines, validation labels, and internal terms when they are useful.
The captain-facing chat summary that points to the report still follows this translation rule.
