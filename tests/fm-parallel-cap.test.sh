#!/usr/bin/env bash
# Guard for the ordinary parallelism cap on fresh ship/scout spawns.
#
# Why a cap at all: concurrency past a handful of lanes stops buying wall clock
# and starts costing supervision. Every extra lane is another pane to reconcile,
# another rebase to settle, and another chance for two workers to collide on one
# file. The captain's own record notes the parallel count getting high and asks
# for tighter close-out rather than fewer workers - which is exactly what a
# metadata-based cap produces, because a finished-but-not-torn-down task keeps
# holding its slot until it is closed out.
#
# The properties that matter:
#   - it refuses AT the cap, and names what is open so the operator can act;
#   - an explicit FM_MAX_PARALLEL is honoured, because this is a cap on ordinary
#     dispatch and the captain may deliberately want more;
#   - secondmates never count, because they are persistent infrastructure;
#   - a relaunch is never blocked, because recovering an existing lane does not
#     widen the fleet.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot parallel-cap)
STATE="$TMP/state"; DATA="$TMP/data"
mkdir -p "$STATE" "$DATA/newtask"

lane() {  # <id> <kind>
  fm_write_meta "$STATE/$1.meta" \
    "window=firstmate:fm-$1" "endpoint_task_id=$1" \
    "worktree=$TMP/w-$1" "project=$TMP/proj" "kind=$2" "mode=local-only"
}

# Runs a fresh spawn and echoes 1 when the CAP refused it, 0 otherwise.
# Other refusals (no worktree, no endpoint) are expected here and ignored: this
# test is about the cap decision, not about completing a real spawn.
cap_refused() {
  local out
  out=$(FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
    "$ROOT/bin/fm-spawn.sh" newtask "$TMP" --mode local-only --yolo off 2>&1 || true)
  case "$out" in
    *"lanes are already open and the ordinary cap is"*) printf 1 ;;
    *) printf 0 ;;
  esac
}

# --- under the cap ------------------------------------------------------------
lane t1 ship; lane t2 ship; lane t3 scout
[ "$(cap_refused)" = 0 ] || fail "three open lanes were refused against a cap of four"
pass "three open lanes are under the cap and dispatch is not blocked"

# --- at the cap ---------------------------------------------------------------
lane t4 ship
[ "$(cap_refused)" = 1 ] || fail "a fourth open lane did not trip the cap of four"
out=$(FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
  "$ROOT/bin/fm-spawn.sh" newtask "$TMP" --mode local-only --yolo off 2>&1 || true)
assert_contains "$out" "t1" "the cap refusal did not name the open lanes"
assert_contains "$out" "bin/fm-teardown.sh" "the cap refusal did not say how to free a slot"
assert_contains "$out" "FM_MAX_PARALLEL" "the cap refusal did not name its deliberate override"
pass "at the cap, dispatch is refused and the refusal names the open lanes and both ways out"

# --- explicit override --------------------------------------------------------
raised=$(FM_MAX_PARALLEL=8 FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
  "$ROOT/bin/fm-spawn.sh" newtask "$TMP" --mode local-only --yolo off 2>&1 || true)
case "$raised" in
  *"already open and the ordinary cap is"*) fail "an explicit FM_MAX_PARALLEL was ignored" ;;
esac
pass "an explicit FM_MAX_PARALLEL is honoured: this caps ordinary dispatch, not the captain"

# --- a malformed cap is an error, not a silent default ------------------------
bad=$(FM_MAX_PARALLEL=lots FM_STATE_OVERRIDE="$STATE" FM_DATA_OVERRIDE="$DATA" \
  "$ROOT/bin/fm-spawn.sh" newtask "$TMP" --mode local-only --yolo off 2>&1 || true)
assert_contains "$bad" "FM_MAX_PARALLEL must be a non-negative integer" \
  "a malformed cap was silently replaced by the default"
pass "a malformed FM_MAX_PARALLEL is an actionable error rather than a silent default"

# --- secondmates are not lanes ------------------------------------------------
rm -f "$STATE"/t4.meta
lane s1 secondmate; lane s2 secondmate; lane s3 secondmate
[ "$(cap_refused)" = 0 ] \
  || fail "persistent secondmates were counted against the ordinary lane cap"
pass "secondmates are persistent infrastructure and never count against the cap"

echo "fm-parallel-cap.test.sh: all assertions passed"
