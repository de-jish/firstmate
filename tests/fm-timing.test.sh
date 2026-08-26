#!/usr/bin/env bash
# Guard for the task timing instrument.
#
# An instrument gets trusted, so the properties that matter are the ones that
# decide whether its numbers can be believed and whether it can hurt anything:
#   - it never fails its caller, because a broken instrument must not break a
#     delivery;
#   - FM_TIMING=off does not touch disk;
#   - a record cannot carry a payload or forge a field (tabs and newlines are
#     stripped, values truncated);
#   - the work/wait split is computed from the event that OPENS each interval;
#   - an interval whose wall and monotonic clocks disagree is REFUSED rather
#     than reported as a duration, so an NTP step cannot invent or erase time.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TIMING="$ROOT/bin/fm-timing.sh"
TMP=$(fm_test_tmproot timing)
LOG="$TMP/timing.log"
export FM_TIMING_LOG="$LOG"

# --- never fails its caller ---------------------------------------------------
"$TIMING" record "" "" >/dev/null 2>&1 || fail "record failed on empty arguments"
"$TIMING" record t1 intake >/dev/null 2>&1 || fail "record failed on a valid event"
FM_TIMING_LOG=/nonexistent-dir-xyz/deep/log "$TIMING" record t1 intake >/dev/null 2>&1 \
  || fail "record failed when its log path was unwritable"
pass "record never fails its caller, even on bad input or an unwritable log"

# Telemetry must never put state back. A secondmate's terminal record is written
# after teardown removed that home, with the log path still inside it, so a
# `record` that created its own directory resurrected the retired home and left
# teardown reporting success over a directory that was back on disk.
GONE="$TMP/removed-home/state"
mkdir -p "$GONE"
rm -rf "$TMP/removed-home"
FM_TIMING_LOG="$GONE/timing.log" "$TIMING" record t1 complete >/dev/null 2>&1 \
  || fail "record failed when its home had already been removed"
[ ! -e "$TMP/removed-home" ] || fail "record recreated a removed home directory"
pass "record never recreates a directory a lifecycle step removed"

# --- disabled writes nothing --------------------------------------------------
rm -f "$LOG"
FM_TIMING=off "$TIMING" record t1 intake >/dev/null 2>&1
[ ! -e "$LOG" ] || fail "FM_TIMING=off still created the log"
pass "FM_TIMING=off returns before touching disk"

# --- no payload, no forged fields ---------------------------------------------
rm -f "$LOG"
"$TIMING" record "task$(printf '\t')x" "ev$(printf '\t')il" \
  "$(printf 'a\tb\nc')-and-a-very-long-tail-that-must-be-truncated-well-before-it-can-carry-anything-meaningful" >/dev/null 2>&1
fields=$(awk -F'\t' 'END{print NF}' "$LOG")
[ "$fields" = 5 ] || fail "a record carried $fields fields; tab injection can forge columns"
[ "$(awk -F'\t' 'END{print length($5)}' "$LOG")" -le 64 ] || fail "detail was not truncated"
[ "$(wc -l < "$LOG" | tr -d ' ')" = 1 ] || fail "a newline in input split one event into several records"
pass "tabs and newlines are stripped and values truncated: a record cannot carry a payload"

# --- work/wait split comes from the opening event ------------------------------
rm -f "$LOG"
sim() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" >> "$LOG"; }
B=1700000000; M=5000
sim $((B+0))    $((M+0))    s1 intake
sim $((B+60))   $((M+60))   s1 worker-requested          # opens a WAIT (60s..160s)
sim $((B+160))  $((M+160))  s1 worker-started            # opens WORK (160s..460s)
sim $((B+460))  $((M+460))  s1 ci-wait-start             # opens a WAIT (460s..1060s)
sim $((B+1060)) $((M+1060)) s1 ci-wait-end               # opens WORK (1060s..1090s)
sim $((B+1090)) $((M+1090)) s1 complete
out=$("$TIMING" summary s1)
# work: intake 0..60 (60s) + worker-started 160..460 (300s) + ci-wait-end 1060..1090 (30s) = 390s = 6m30s
# wait: worker-requested 60..160 (100s) + ci-wait-start 460..1060 (600s)              = 700s = 11m40s
assert_contains "$out" "6m30s" "work total was not computed from the opening events"
assert_contains "$out" "11m40s" "wait total was not computed from the opening events"
assert_contains "$out" "ci-wait-start" "the longest wait was not attributed to the right event"
pass "the work/wait split is computed from the event that opens each interval"

# --- a clock disagreement is refused, not reported -----------------------------
rm -f "$LOG"
sim $((B+0))    $((M+0))   s2 intake
sim $((B+3660)) $((M+60))  s2 worker-started   # wall +1h, monotonic +60s: NTP step
sim $((B+3720)) $((M+120)) s2 complete
out=$("$TIMING" summary s2)
assert_contains "$out" "clocks disagreed" "an interval with disagreeing clocks was scored instead of refused"
case "$out" in
  *"1h00m"*) fail "the bogus hour from the clock step was reported as real work" ;;
esac
pass "an interval whose wall and monotonic clocks disagree is refused, not reported"

# --- retire removes only that task --------------------------------------------
rm -f "$LOG"
sim $((B+0)) $((M+0)) keep intake
sim $((B+1)) $((M+1)) drop intake
"$TIMING" retire drop >/dev/null 2>&1
assert_grep "keep" "$LOG" "retire removed a task it was not asked to remove"
assert_no_grep "drop" "$LOG" "retire did not remove the named task"
pass "retire removes exactly the named task's rows"

echo "fm-timing.test.sh: all assertions passed"
