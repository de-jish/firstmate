# Adaptive delivery: the measured baseline and what changed

This document records the evidence behind the `adaptive` delivery mode and the
watcher quiet-state repair.
It exists so the design can be argued with rather than taken on faith, and so a
later change can tell whether it helped.

Everything in "Measured baseline" was reconstructed from this checkout and the
project's own history.
Everything marked NOT MEASURED is exactly that; none of it has been estimated
and none of it should be quoted as if it had been.

## Evidence sources

Reconstruction used git author dates (which survive rebases, unlike committer
dates, several of which were flattened), the GitHub Actions API, the pull
request API, and `data/<id>/brief.md` mtimes.

`state/<id>.status` and `state/<id>.meta` no longer exist for any completed
task - teardown removes them - and `.no-mistakes/` is empty in both this home
and the project clone.
That is the direct reason `bin/fm-timing.sh` now exists: the records that would
have made this a five-minute read had already been cleaned up.

Population: the twelve firstmate-run ship tasks on `de-jish/iMeetStand` that
reached a merged PR (`fm/*` branches, PRs #24-#37, 2026-08-21 to 2026-08-23).

## Measured baseline

| task | PR | coding | review loop | rounds | code -> CI green | green -> merge |
|---|---|---|---|---|---|---|
| sheet-grabber-remove-f1 | 24 | 2m | 0m | 0 | n/a | n/a |
| meetie-intro-tap-gate-f2 | 25 | 0m | 0m | 0 | n/a | n/a |
| social-panel-resize-d1 | 26 | 0m | 0m | 1 | n/a | n/a |
| cd-five-surfaces-not-block-aware-r24 | 27 | 0m | 7h40m | 6 | 8h47m | 1m |
| cd-user-scores-orphans-r20 | 28 | 0m | 7h32m | 11 | 19h37m | 0m |
| social-panel-resize-build-r47 | 29 | 23m | 34m | 2 | 13h00m | 0m |
| reclaim-identity-pin-r59 | 31 | 0m | 0m | 1 | 50m | 1m |
| reels-initial-load-r65 | 32 | 0m | 37m | 4 | 1h38m | 2m |
| breakroom-fixes-r69 | 33 | 0m | 6h34m | 6 | 7h58m | 3m |
| inbox-filter-transitions-r70 | 34 | 0m | 7h06m | 7 | 8h03m | 4m |
| reader-polish-v3 | 36 | 0m | 32m | 3 | 1h26m | 15h27m |
| social-answerable-q5 | 37 | 56m | 58m | 6 | 2h14m | 13h45m |

Aggregates across all twelve:

| stage | total | share of agent path |
|---|---|---|
| coding (first commit to implementation complete) | **1h23m** | 2% |
| AI review fix-loop (47 fix commits) | **31h37m** | 49% |
| documentation stage | 9m | <1% |
| CI execution (every run summed) | 2h02m | 3% |
| **agent-controlled critical path** (code to CI green) | **64h57m** | 100% |
| captain latency (CI green to merge) | 29h26m | separate |

Splitting the agent path by whether anything was happening:

| | total | share |
|---|---|---|
| active (consecutive commits within 30 min) | 15h17m | **24%** |
| idle (gaps over 30 min between commits) | **51h03m** | **76%** |

### The three findings that drove the design

**1. Coding is not the bottleneck; it is a rounding error.**
1h23m of coding against 64h57m of agent-controlled wall clock. Any change aimed
at making the model write code faster is aimed at 2% of the problem.

**2. The uniform review fix-loop is the largest single work item.**
31h37m across 47 fix commits, roughly 23x the coding time. The loop ran at the
same intensity regardless of what the change was: an 11-round loop on an orphan
reclaim, a 7-round loop on a UI transition fix.

Marginal value per round, measured by files touched:

| round | tasks reaching it | avg files touched |
|---|---|---|
| 1 | 10 | 8.7 |
| 2 | 8 | 7.1 |
| 3 | 7 | 4.3 |
| 4 | 6 | 4.3 |
| 5 | 5 | 4.8 |
| 6+ | 5 | ~4-6 |

Rounds 1-2 account for 52% of all review-fix file touches in 18 of 47 rounds;
rounds 3+ take 29 rounds for the remaining 48%.

**Stated honestly: this does not show later rounds are worthless.** They keep
touching four to six files. What it shows is that the marginal round costs about
40 minutes of wall clock (31h37m / 47) for roughly half the change of an early
one. That is a cost argument for capping the automatic loop and escalating,
not evidence that the reviewer was wrong.

**3. Three quarters of the critical path is nothing happening at all.**
51h03m idle. Four open upstream defects explain the shape, and this fork
carried all four - verified by reading the code, not by assuming:

| issue | present in this fork? | evidence |
|---|---|---|
| #3057 workers background a pipeline call and end the turn, parking the run | yes | `bin/fm-brief.sh` never forbade it |
| #3061 parked workers self-poll, invisibly | yes | no brief rule against it |
| #3055 watcher wedge-escalates a lane correctly parked at a gate | yes | `pause_state_class` only recognised a *declared* `paused:` line |
| #2968 finished task awaiting merge emits a stale wake every cycle | yes | same predicate; `done` + `pr=` was not a quiet state |
| #3071 `fm-crew-state` reports a stale failed run as current | yes | `nm_runs_status_for_branch` matches the *worktree* head, so a pipeline-owned advanced head is skipped |
| #3075 teardown can reset a pool worktree reallocated to a live task | yes | `fm-teardown.sh` has no cross-check of other metas |

**Caveat on attribution.** Commit gaps show *that* a lane was idle, not *why*.
Some of the 51h03m is the captain asleep rather than a lane wedged, and the
records that would separate them were torn down. The four defects above are
verified present in the code; their exact share of the 51h03m is NOT MEASURED.

### Not measured

- **Worker spawn latency.** `brief.md` mtime is the only proxy and it is
  confounded by queueing: several tasks were briefed hours before dispatch.
- **Per-stage validation split** (focused tests vs lint vs docs vs full suite).
  No surviving logs.
- **Captain notification delay.** Never recorded anywhere.
- **Agent turn counts.** Not recoverable from git or the API.

`bin/fm-timing.sh` records all four going forward.

## What changed

### Adaptive mode and its tiers

`bin/fm-tier-lib.sh` owns the tier set, the high-risk surface list, and each
tier's authorized check plan. Nothing else restates them.

Classification is fail-safe-upward: any high-risk surface forces
`comprehensive` and no fast-looking signal can talk it down, while unknown
ordinary work resolves to `standard` rather than `comprehensive`. Misclassifying
downward risks shipping an unvalidated auth change; misclassifying upward only
costs time.

### Measured scenario results

`tests/fm-adaptive-scenarios.test.sh` builds a disposable fixture with a web
package, an api package, lint, focused tests, a full suite, a device matrix, and
an AI review step, injects a defect, and **executes both check sets**:

| scenario | tier | uniform | tier-scoped | checks | defect caught by |
|---|---|---|---|---|---|
| one-file copy change | fast | 7599ms | 366ms | 9 -> 2 | focused test |
| feature across web + api | standard | 6219ms | 1430ms | 9 -> 6 | focused test |
| privacy disclosure | comprehensive | 6205ms | 1268ms | 9 -> 4 | privacy suite |

20023ms uniform to 3064ms tier-scoped, 85% less, **with every injected defect
still caught**.

The harness also proves the escalation is load-bearing rather than decorative:
the privacy defect is invisible to the focused behaviour test, so the standard
tier's check set would have MISSED it. Forcing `comprehensive` on that surface
buys real signal.

**This is validation cost only.** Agent turns, review-loop rounds, and captain
latency are not measured by that harness and are not claimed.

### Watcher quiet states

`crew_absorb_class` now returns the existing `paused` class - which the watcher
already answers with a long recheck cadence instead of a wedge alarm - for a run
parked at a gate (#3055) and a finished task awaiting a merge decision (#2968).

Two limits keep this from weakening real wedge detection:

- Only a **run-step-sourced** park is trusted, because that verdict comes from
  the pipeline's own step state rather than a pane that merely looks idle.
- The merge-wait state additionally requires the merge poll to be **armed**,
  which happens only after firstmate handled the `done:` and relayed the PR. It
  therefore cannot swallow the first surfacing of a finished task, only the
  repeated alarms after it. That poll is already the task's wake path, which is
  what makes the stale channel redundant while it is armed.

Going quiet never suppresses an open decision: the durable open-decision fold is
a separate path from wedge detection, and `tests/fm-quiet-state.test.sh` asserts
that directly.

### Brief-level park repairs

Every ship brief now states the consequence, not just the rule: backgrounding a
long validation call and ending the turn leaves nobody listening when it
returns, and a parked worker never needs to self-poll because a steer is
delivered into its composer and wakes it.

## Collecting a real before-and-after

The validation-cost number above is measured. The wall-clock number is not, and
cannot be without real runs. To get one:

1. Leave `bin/fm-timing.sh` recording (it is on by default and costs one
   appended line per event).
2. Run several ordinary tasks under `adaptive`.
3. Compare `bin/fm-timing.sh summary` against the baseline table above.

The comparison that matters is **agent-controlled critical path** and the
**work/wait split**, not total wall clock: total includes captain latency, which
is deliberately preserved.
