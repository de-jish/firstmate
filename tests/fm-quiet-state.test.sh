#!/usr/bin/env bash
# Behavior guard for the two legitimate QUIET states a lane can rest in.
#
# Measured origin: across twelve shipped ship-tasks, 76% of the agent-controlled
# critical path was idle rather than working. Two upstream defects explain the
# bulk of it, and both are about the watcher failing to tell "silent because
# waiting" apart from "silent because wedged":
#
#   kunchenguid/firstmate#3055 - a lane correctly parked at a validation gate is
#     read as a wedge and escalated. One lane reached 671 consecutive wedge
#     escalations; each one costs a full supervision turn.
#   kunchenguid/firstmate#2968 - a finished ship task whose PR is open but not
#     yet merged emits a stale wake every watcher cycle, for as long as the
#     human merge decision takes (measured here at up to 15h27m).
#
# crew_absorb_class is the one place that verdict is made, so these assertions
# pin its behavior directly. The safety property asserted last is the one that
# makes the whole change acceptable: going quiet must never be able to swallow
# the FIRST surfacing of a finished task, nor an open decision.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot quiet-state)
STATE="$TMP/state"
mkdir -p "$STATE"

# Stub the crew-state reader so the verdict under test is the mapping, not a
# real worktree or a no-mistakes install.
STUB="$TMP/crew-state-stub.sh"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
# Emits the line recorded for this id, or nothing.
f="$FM_TEST_VERDICTS/$1"
[ -f "$f" ] && cat "$f"
SH
chmod +x "$STUB"
mkdir -p "$TMP/verdicts"
export FM_TEST_VERDICTS="$TMP/verdicts"
export FM_CREW_STATE_BIN="$STUB"
export STATE

# shellcheck source=bin/fm-classify-lib.sh
. "$ROOT/bin/fm-classify-lib.sh"

verdict() { printf '%s\n' "$2" > "$FM_TEST_VERDICTS/$1"; }

# --- baseline vocabulary is unchanged ----------------------------------------
verdict w 'state: working · source: run-step · validating (running)'
[ "$(crew_absorb_class w)" = working ] || fail "run-step working no longer classes working"
verdict p 'state: paused · source: status-log · declared wait'
[ "$(crew_absorb_class p)" = paused ] || fail "declared pause no longer classes paused"
verdict u 'state: unknown · source: none · no evidence'
[ "$(crew_absorb_class u)" = none ] || fail "unknown no longer classes none"
pass "existing working/paused/none classification is unchanged"

# --- #3055: a run parked at a gate is a wait, not a wedge ---------------------
verdict parked 'state: parked · source: run-step · review gate awaiting response'
[ "$(crew_absorb_class parked)" = paused ] \
  || fail "a run-step parked gate still classes as a wedge candidate (#3055 unfixed)"
crew_is_paused parked || fail "crew_is_paused does not recognize a parked gate"
pass "#3055: a run parked at a validation gate rests on the long recheck cadence"

# --- a parked verdict from a mere idle pane is NOT trusted --------------------
# Only the pipeline's own step state proves a park. A pane-sourced park would let
# any quiet terminal silence real wedge detection.
verdict parkedpane 'state: parked · source: pane · pane looks idle'
[ "$(crew_absorb_class parkedpane)" = none ] \
  || fail "a pane-sourced park was trusted; only run-step may prove a park"
pass "only a run-step-sourced park is trusted; an idle pane still escalates"

# --- #2968: done + recorded PR + ARMED poll is a merge wait -------------------
verdict m 'state: done · source: status-log · PR https://example.invalid/pull/1'
# Not yet relayed: no armed poll, so this must still surface.
[ "$(crew_absorb_class m)" = none ] \
  || fail "a finished task went quiet BEFORE its PR was relayed - the first surfacing was swallowed"
printf 'pr=https://example.invalid/pull/1\n' > "$STATE/m.meta"
[ "$(crew_absorb_class m)" = none ] \
  || fail "meta pr= alone silenced the task; the armed poll is required"
: > "$STATE/m.check.sh"
[ "$(crew_absorb_class m)" = paused ] \
  || fail "a finished task with a recorded PR and an armed merge poll still wedge-escalates (#2968 unfixed)"
pass "#2968: a finished task awaiting a merge decision goes quiet only AFTER its PR is relayed"

# --- the armed poll is load-bearing in both directions ------------------------
rm -f "$STATE/m.check.sh"
[ "$(crew_absorb_class m)" = none ] \
  || fail "task stayed quiet after its merge poll was retired; the wake path was gone with nothing watching"
pass "retiring the merge poll returns the task to ordinary surfacing"

# --- a done task with NO pr= never goes quiet ---------------------------------
verdict d2 'state: done · source: status-log · finished'
: > "$STATE/d2.check.sh"
[ "$(crew_absorb_class d2)" = none ] \
  || fail "a done task with no recorded PR went quiet on an armed poll alone"
pass "a finished task with no recorded PR always surfaces"

# --- SAFETY: quiet never suppresses an open decision --------------------------
# The open-decision fold is a separate path from wedge detection, so a lane that
# is quiet for merge or gate reasons still reports its open decisions.
cat > "$STATE/q.status" <<'LOG'
working: started
needs-decision: [key=tier-check] which tier applies here
done: PR https://example.invalid/pull/9
LOG
printf 'pr=https://example.invalid/pull/9\n' > "$STATE/q.meta"
: > "$STATE/q.check.sh"
verdict q 'state: done · source: status-log · PR https://example.invalid/pull/9'
[ "$(crew_absorb_class q)" = paused ] || fail "merge-wait quiet state not reached for the safety case"
open=$(status_open_decisions "$STATE/q.status")
assert_contains "$open" "tier-check" "an open decision was lost while the lane rested in a quiet state"
pass "SAFETY: a quiet lane still reports its open decisions"

echo "fm-quiet-state.test.sh: all assertions passed"
