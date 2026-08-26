#!/usr/bin/env bash
# Scenario harness for the adaptive delivery mode.
#
# WHAT THIS MEASURES, AND WHAT IT DOES NOT.
#
# It builds a disposable fixture repo with a web package, an api package, a
# lint step, focused tests, a slow full suite, and a slow device matrix. It then
# runs three scenarios, and for each one executes BOTH check sets end to end:
# the uniform set (what a full-pipeline mode runs regardless of the change) and
# the tier-scoped set the adaptive contract authorizes. Execution time and
# defect detection are MEASURED by running the commands, not asserted from a
# step count.
#
# It does NOT measure agent wall clock. The review fix-loop, the number of agent
# turns, and captain latency depend on real model runs, so this harness cannot
# and does not claim a number for them. Those must come from bin/fm-timing.sh on
# real tasks. Anything printed here is validation cost only.
#
# The assertions that make this a guard rather than a demo are the last two per
# scenario: the tier must still catch the injected defect, and a scenario that
# touches a high-risk surface must still be classed comprehensive.
#
# The fixture check bodies below are single-quoted ON PURPOSE: $FIXROOT must
# expand when the fixture check RUNS, not when this file writes it.
# shellcheck disable=SC2016
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TIERLIB="$ROOT/bin/fm-tier-lib.sh"
TMP=$(fm_test_tmproot adaptive-scen)
FIX="$TMP/fixture"

# --- fixture ------------------------------------------------------------------
# Costs are deliberate and fixed so the comparison is about WHICH checks run,
# not about machine speed. They are ordered the way a real repo's are: focused
# tests are cheap, the full suite and the device matrix are not.
mkdir -p "$FIX/web" "$FIX/api" "$FIX/checks"
mk() { printf '%s\n' "$2" > "$FIX/checks/$1"; chmod +x "$FIX/checks/$1"; }

mk lint-changed '#!/usr/bin/env bash
sleep 0.05
grep -qs "BADSTYLE" "$FIXROOT"/web/*.css 2>/dev/null && { echo "lint-changed: style violation"; exit 1; }
exit 0'
mk lint-web '#!/usr/bin/env bash
sleep 0.2
grep -qs "BADSTYLE" "$FIXROOT"/web/*.css 2>/dev/null && { echo "lint-web: style violation"; exit 1; }
exit 0'
mk lint-api '#!/usr/bin/env bash
sleep 0.2
exit 0'
mk test-focused '#!/usr/bin/env bash
sleep 0.1
# Covers exactly the behavior the change touched. Deliberately BLIND to the
# privacy defect: a disclosure bug is precisely the class a behavior test for
# the changed feature does not see, which is why that surface earns its own check.
[ -f "$FIXROOT/.defect-copy" ]    && { echo "test-focused: copy assertion failed"; exit 1; }
[ -f "$FIXROOT/.defect-feature" ] && { echo "test-focused: feature assertion failed"; exit 1; }
exit 0'
mk test-full '#!/usr/bin/env bash
sleep 1.2
[ -f "$FIXROOT/.defect-copy" ]    && { echo "test-full: copy assertion failed"; exit 1; }
[ -f "$FIXROOT/.defect-feature" ] && { echo "test-full: feature assertion failed"; exit 1; }
[ -f "$FIXROOT/.defect-privacy" ] && { echo "test-full: privacy assertion failed"; exit 1; }
exit 0'
mk device-matrix '#!/usr/bin/env bash
sleep 1.5
exit 0'
mk build-web '#!/usr/bin/env bash
sleep 0.3
exit 0'
mk build-api '#!/usr/bin/env bash
sleep 0.3
exit 0'
mk smoke '#!/usr/bin/env bash
sleep 0.2
exit 0'
mk privacy-suite '#!/usr/bin/env bash
sleep 0.4
[ -f "$FIXROOT/.defect-privacy" ] && { echo "privacy-suite: discloses personal data"; exit 1; }
exit 0'
mk ai-review '#!/usr/bin/env bash
sleep 2.0
exit 0'

export FIXROOT="$FIX"

# The uniform set: what a full-pipeline mode runs for ANY change.
UNIFORM="lint-web lint-api test-focused test-full device-matrix build-web build-api smoke ai-review"

# Run a named check set; echo "<elapsed-ms> <failed-check-or-none> <count>".
run_set() {
  local set_name=$1 start end failed=none n=0 c
  start=$(python3 -c 'import time;print(int(time.time()*1000))')
  for c in $set_name; do
    n=$((n + 1))
    if ! "$FIX/checks/$c" >/dev/null 2>&1; then
      [ "$failed" = none ] && failed=$c
    fi
  done
  end=$(python3 -c 'import time;print(int(time.time()*1000))')
  printf '%s %s %s' "$((end - start))" "$failed" "$n"
}

clear_defects() { rm -f "$FIX"/.defect-*; }

# --- scenario driver ----------------------------------------------------------
printf '\n%s\n' "=== adaptive scenarios: measured validation cost and defect detection ==="
printf '%-26s %-14s %7s %7s %6s %6s  %s\n' \
  scenario tier uniform adaptive u_chk a_chk 'injected defect caught by'
printf '%s\n' "--------------------------------------------------------------------------------------------"

TOTAL_U=0
TOTAL_A=0

scenario() {  # <label> <description> <defect-flag> <adaptive-check-set> <expected-tier>
  local label=$1 desc=$2 defect=$3 aset=$4 want_tier=$5
  local tier reason u a ufail ucnt afail acnt

  tier=$("$TIERLIB" classify "$desc" | cut -f1)
  reason=$("$TIERLIB" classify "$desc" | cut -f2)
  [ "$tier" = "$want_tier" ] \
    || fail "$label classified '$tier', expected '$want_tier' ($reason)"

  clear_defects; : > "$FIX/.defect-$defect"
  read -r u ufail ucnt <<<"$(run_set "$UNIFORM")"
  clear_defects; : > "$FIX/.defect-$defect"
  read -r a afail acnt <<<"$(run_set "$aset")"
  clear_defects

  [ "$ufail" != none ] || fail "$label: the uniform set did not catch the injected defect either - fixture is wrong"
  [ "$afail" != none ] \
    || fail "$label: the $tier tier MISSED the injected defect (uniform caught it at $ufail)"

  printf '%-26s %-14s %6sms %6sms %6s %6s  %s\n' \
    "$label" "$tier" "$u" "$a" "$ucnt" "$acnt" "$afail"
  TOTAL_U=$((TOTAL_U + u)); TOTAL_A=$((TOTAL_A + a))
}

# 1. one-file copy / styling change -> fast
scenario "1 one-file copy change" \
  "Fix the wording on the empty-library placeholder copy" \
  copy "lint-changed test-focused" fast

# 2. ordinary feature split across web and api -> standard
scenario "2 feature web+api" \
  "Let a reader rename a folder from the library view" \
  feature "test-focused lint-web lint-api build-web build-api smoke" standard

# 3. privacy change -> comprehensive, scoped to the risk actually touched
scenario "3 privacy disclosure" \
  "Stop disclosing personal data in the shared activity feed" \
  privacy "test-focused privacy-suite lint-web build-web" comprehensive

printf '%s\n' "--------------------------------------------------------------------------------------------"
printf '%-26s %-14s %6sms %6sms\n' TOTAL "" "$TOTAL_U" "$TOTAL_A"
python3 - "$TOTAL_U" "$TOTAL_A" <<'PY'
import sys
u,a=int(sys.argv[1]),int(sys.argv[2])
print(f"\nmeasured validation cost across the three scenarios: {u}ms uniform -> {a}ms tier-scoped "
      f"({100*(u-a)/u:.0f}% less), with every injected defect still caught.")
print("This is validation cost only. Agent turns, review-loop rounds, and captain latency are NOT")
print("measured here; collect those with bin/fm-timing.sh on real tasks.")
PY
pass "every tier caught its injected defect while running fewer checks than the uniform set"

# --- the escalation to comprehensive is load-bearing --------------------------
# If the standard tier's check set would have caught the privacy defect anyway,
# forcing comprehensive would be cost with no signal. Prove it would NOT.
clear_defects; : > "$FIX/.defect-privacy"
read -r _ sfail _ <<<"$(run_set "test-focused lint-web lint-api build-web build-api smoke")"
clear_defects
[ "$sfail" = none ] \
  || fail "the standard set caught the privacy defect, so forcing comprehensive proves nothing here"
pass "the standard tier would MISS the privacy defect: forcing comprehensive on that surface is load-bearing"

# --- safety gates are preserved ----------------------------------------------
# The speed claim is only acceptable if the gates still refuse. These assert the
# refusals directly rather than trusting the contract text.
SP="$TMP/briefs"; mkdir -p "$SP/data" "$SP/state"
export FM_DATA_OVERRIDE="$SP/data" FM_STATE_OVERRIDE="$SP/state"

"$ROOT/bin/fm-brief.sh" g1 repo --mode adaptive >/dev/null 2>&1 \
  && fail "adaptive brief scaffolded with no tier"
"$ROOT/bin/fm-brief.sh" g2 repo --mode adaptive --tier turbo >/dev/null 2>&1 \
  && fail "adaptive brief accepted an unknown tier"
"$ROOT/bin/fm-brief.sh" g3 repo --mode direct-PR --tier fast >/dev/null 2>&1 \
  && fail "a tier was accepted on a non-adaptive mode"
pass "SAFETY: adaptive refuses to scaffold without a valid tier, and no other mode accepts one"

"$ROOT/bin/fm-brief.sh" g4 repo --mode adaptive --tier fast >/dev/null 2>&1 \
  || fail "a valid adaptive brief failed to scaffold"
B="$SP/data/g4/brief.md"
assert_contains "$(cat "$B")" "Delivery contract: mode=adaptive tier=fast" "brief must record its tier machine-readably"
assert_contains "$(cat "$B")" "Verify isolation before anything else" "worktree isolation assertion must survive in every ship brief"
assert_contains "$(cat "$B")" "Never push to the default branch" "push protection must survive"
assert_contains "$(cat "$B")" "Never merge a PR" "merge protection must survive"
assert_contains "$(cat "$B")" "ONE automatic repair attempt" "the one-repair-loop cap must be stated"
assert_contains "$(cat "$B")" "Never background a long-running validation" "the park repair must be in the brief"
assert_contains "$(cat "$B")" "park SILENTLY" "the self-poll repair must be in the brief"
pass "SAFETY: isolation, push, and merge protections survive at the fastest tier"

# A fast-tier brief must not quietly authorize a reviewer or a full suite.
assert_contains "$(cat "$B")" "Do NOT run the full repository test suite" "fast brief must forbid the full suite"
assert_contains "$(cat "$B")" "Do NOT request or spawn an independent AI reviewer" "fast brief must forbid a reviewer"
pass "SAFETY: the fast tier cannot silently re-acquire a reviewer or the full suite"

echo "fm-adaptive-scenarios.test.sh: all assertions passed"
