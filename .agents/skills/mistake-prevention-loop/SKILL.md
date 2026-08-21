---
name: mistake-prevention-loop
description: >-
  Agent-only procedure for turning a caught mistake into a repository change that prevents it.
  Load when a repository gate, guard, or script refuses one of firstmate's own actions, when a review or validation finding against firstmate's own conduct or instructions is confirmed, when the captain corrects firstmate or points out something firstmate got wrong, or when firstmate needs a recovery path because of its own earlier error.
  Owns the mechanism statement, the strongest-feasible-prevention ladder, the proof that the guard catches the original failure, and the anti-patterns that look like closure without being it.
user-invocable: false
metadata:
  internal: true
---

# Mistake prevention loop

A mistake we caught becomes a mistake the repository prevents.
This loop is standing and non-optional: every trigger below runs it to completion, in this session, for the shared surface every firstmate home loads.

It exists because the default ending is too weak.
A caught mistake gets fixed in the instance, and at best written into `data/learnings.md`, which is private to one home and reaches no other agent.
Nothing else obliged firstmate to strengthen the shared surface, and nothing checked that it had.

## When to load

Load this skill when any of these happens:

- A repository gate, guard, or script refuses one of firstmate's own actions.
- A review or validation finding against firstmate's own conduct or instructions is confirmed.
- The captain corrects firstmate, or points out something firstmate got wrong.
- Firstmate needs a recovery path because of its own earlier error.

A refusal that correctly stopped a wrong action is still a trigger: the guard worked, and the question is why the wrong action was reachable at all.
A finding that turns out to be wrong is not a trigger; confirm it first.
Another project's bug, a vendor defect, and an external outage are not triggers unless firstmate's own handling of them was wrong.

## Procedure

1. **State the mistake as a mechanism, not a lapse.**
   "I forgot" is not a cause and cannot be prevented, so it is never an acceptable statement of one.
   Name the thing that was possible, what it left behind, and what failed to notice: "closing a hold through a tool that is not its owner leaves no durable record, and nothing detected it" is a cause and can be prevented.
   Separate the sub-mechanisms when a single incident has several, because each may need a different prevention.
2. **Choose the strongest feasible prevention, not the easiest.**
   Work the ladder below from the top, and record why anything stronger than what you chose was rejected.
   An unrecorded rejection is not a rejection; it is the easy tier wearing the strong tier's language.
3. **Prove the guard works.**
   Reproduce the original mistake against the guard, observe the refusal or detection, then revert the reproduction.
   A guard that has not been shown to catch the thing it was written for is not a guard.
   The reproduction must be the original failure, not the guard's own code path.
4. **Record the evidence** where `firstmate-coding-guidelines` says maintainer verification belongs, with the date, the exact commands, and the exact output that supports the current guarantee.
5. **Prefer strengthening an existing owner** over adding a new surface, per that skill's one-owner rule.
   A defect a current owner is already closest to belongs to that owner, extended; a second surface that partially restates it will drift.

`firstmate-coding-guidelines` owns how to make the change itself: knowledge placement, the one-owner rule, size discipline, trigger hygiene, and repo style.
Load it before editing, as `AGENTS.md` section 1 requires for shared tracked material.

## The prevention ladder

Strongest first.
Stop at the strongest tier that is genuinely feasible, and state in the change's own evidence why each stronger tier was not.

1. **Make it impossible.**
   A script or guard refuses the wrong action outright.
   Prefer the owner refusing its own misuse over an outside interceptor, because the owner sees the real arguments and cannot be bypassed by a different caller.
2. **Make it detected.**
   A check surfaces the wrong state at session start or at the next natural gate.
   Detection must reach a home that never happens to run the gate the incident happened to trip, and it must be placed so that whatever normally erases the evidence - retention, cleanup, teardown - does not erase it first.
   Any gap that survives that placement is stated in the change's own evidence rather than left for the next incident to find.
3. **Make it instructed.**
   The shared instruction surface tells the next agent, in any home, at the moment it matters.
   An instruction is a real prevention only when no mechanical check could have carried it.
4. **Make it recorded.**
   A home-local learning in `data/learnings.md`.
   This is the weakest option, it reaches exactly one home, and it is never sufficient on its own when a stronger tier was feasible.

Tiers compose.
A detection usually needs a matching instruction for how to respond to what it detects, and that pairing is one prevention, not two.

"Not feasible" is a claim about this repository, and it needs a concrete reason: the surface does not exist and building it would exceed the change, the mechanism is fail-open and so cannot be load-bearing, or the condition is legitimate to create and can only be caught after the fact.
"Harder" and "more code" are not reasons; the marginal cost of the stronger tier is not the captain's problem.

## Anti-patterns

Each of these is a way of appearing to close the loop without closing it.

- Writing a learning and calling it done when a script guard was feasible.
- Adding an instruction where a mechanical check was feasible.
- A guard whose test asserts the guard's own code path rather than the original failure.
- Fixing the instance and deferring the prevention.
- Treating the captain noticing as the correction, rather than as evidence the loop was missing.
- Shipping a guard whose printed remediation is destructive when its scope is wrong.
- Fixing the site a finding names when the finding is really about a class, instead of sweeping for the class first.
- Accepting a behavioural remedy - "I will remember to X", "next time I will check Y" - as the prevention.

The captain-noticing one is the most expensive, because it hides the real defect.
The captain noticing means detection was absent, so the prevention owed is detection, not an apology and a fixed instance.

The scope one is the way this loop turns against itself.
A detector that names the wrong subject does not merely cry wolf.
If the remediation it prints mutates state, a wrong subject means the guard manufactures a false record that carries the authority of a correction, which is the exact harm this loop exists to prevent.
The session-start captain-decision audit in `bin/fm-decision-hold.sh` is the worked example: its first version admitted any identity carrying tasks-axi's `hold_kind: captain`, which `AGENTS.md` section 10 prescribes for every captain-gated thread, so an ordinary captain thread whose id merely spelled `-decision-` was reported as a decision closed without an answer, and the `repair` command the report printed then wrote a fabricated resolution block onto that unrelated thread.
Two checks follow from it.
Before shipping a guard, ask what its printed remediation does when the scope is wrong, and scope on signals the guard's own owner writes rather than on ones any neighboring workflow also writes.
Then prove the scope on the nearest legitimate lookalike, not on the failing case alone: a guard proven only against the mistake it was written for has been shown to fire, never shown to hold its edge.

The sweep one costs a review round per site left standing.
Some defects are a class rather than a place: a remediation gated on the wrong test, a control that cannot fire, a claim pinned to something that moves.
When the defect is one of those, the first fix is the sweep, not the patch, and the anti-pattern is not "we missed a site" but "we fixed a site" - fixing the instance in front of you and moving on leaves the class intact everywhere else, and every remaining site costs another round to find.
The destructive-remediation defect above is the worked example: it was fixed at the audit in one round, found again at `command_hold` in a later one, and only a deliberate sweep then turned up a third site in `close_unrouted_hold` that predated the branch and whose blast radius the branch had quietly enlarged.
The check this implies: when a finding names a test, a gate, or a condition used in one place, ask what else uses it before fixing it, and report the sweep result even when it is empty, because "I looked and there is one site" and "I fixed the site I was shown" read identically in a diff and mean opposite things.

The behavioural one is below the bottom of the ladder, not above it.
An intention is weaker than the recorded rung: a learning at least persists and can be read by the next agent, while "I will remember" can be checked by nobody and decays immediately.
The worked example is this loop's own validation run, recorded because the evidence is unusually direct.
The worker deadlocked with its own pipeline - the run sat at a `*_review` state waiting for a response while the worker waited for a gate that had already arrived - then diagnosed the failure correctly, proposed "I will poll to an outcome rather than announcing and going quiet", and broke that remedy inside a single round.
The agent that had just named the failure and chosen the remedy could not hold it for one round, which is the whole argument.
The rule that follows: a guard for a class must hold when the worker forgets, because the worker demonstrably will, so "the worker will remember" is never the prevention.
What does hold is structural - a check at the moment of failure, a refusal, or a mechanism that surfaces the condition without anyone choosing to look.
That incident also produced the checkable discriminator such a guard would read, worth recording because the obvious signal is the wrong one: a step's elapsed duration can be frozen while the run around it progresses, so duration is not a liveness signal, while the step's status value is - a step sitting at any `*_review` state means the run is waiting for the worker, readable directly with no inference.

A new guard's first version also gets checked against the contracts the repository already enforces, because a guard is new code in an old system and inherits every rule that system already has.
The same audit's first version wrote to the home's state directory on a detect-only session start, which the repository's own harness test refuses, and it was the second guard that day to break that contract.
A contract two guards broke in one day is one the next guard will break too unless its author goes looking for it.

## Boundary

This loop strengthens the shared surface, and it stops there.

- It never rewrites history: it does not edit, reinterpret, or delete the record of what happened.
- It never weakens an existing gate to make a failure go away.
  A gate that refused correctly stays exactly as strict; if a gate refused wrongly, that is its own defect with its own mechanism, and it is fixed as one.
- It never converts a captain decision into an inferred rule.
  A decision the captain made once governs what they said it governs; standing rules come from the captain saying so.

The captain-word actions in `AGENTS.md` section 9 remain captain-word actions, and nothing this loop produces is authority to take one.
