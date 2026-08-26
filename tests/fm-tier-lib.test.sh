#!/usr/bin/env bash
# Behavior guard for the adaptive delivery mode's validation tiers.
#
# The tier is what makes `adaptive` proportional rather than uniform, so the
# properties asserted here are the ones that would silently un-fix the measured
# problem if they regressed:
#   - a high-risk surface ALWAYS forces comprehensive and cannot be talked down
#     by a fast-looking word in the same sentence;
#   - unknown ordinary work lands on standard, never comprehensive (the whole
#     point is not paying full freight by default) and never fast;
#   - each tier's check plan actually forbids what that tier is meant to skip,
#     because the plan text IS the contract the worker follows.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TIER="$ROOT/bin/fm-tier-lib.sh"

tier_of() { "$TIER" classify "$1" | cut -f1; }

# --- closed set --------------------------------------------------------------
for t in fast standard comprehensive; do
  "$TIER" validate "$t" >/dev/null 2>&1 || fail "tier '$t' rejected by validate"
done
for t in turbo FAST '' exhaustive; do
  "$TIER" validate "$t" >/dev/null 2>&1 && fail "tier '$t' accepted by validate"
done
pass "tier validate accepts exactly fast/standard/comprehensive"

# --- unknown ordinary work defaults to standard -------------------------------
for d in \
  "Add a folder rename feature to the library view" \
  "Fix the score list ordering when two scores share a title" \
  "Let readers resize the social panel" \
  "Something entirely unclassifiable zzzqqq"
do
  got=$(tier_of "$d")
  [ "$got" = standard ] || fail "unknown ordinary work classed '$got', expected standard: $d"
done
pass "unknown ordinary work defaults to standard (not comprehensive, not fast)"

# --- every named high-risk surface forces comprehensive ------------------------
while IFS='|' read -r desc surface; do
  [ -n "$desc" ] || continue
  got=$(tier_of "$desc")
  [ "$got" = comprehensive ] || fail "$surface work classed '$got', expected comprehensive: $desc"
done <<'CASES'
Add rate limiting to the login endpoint|authentication
Tighten the RLS policy on the scores table|permission boundary
Stop collecting personal data in analytics|privacy
Add a migration to backfill the answers table|migration
Wire up the Stripe checkout flow|payments
Rotate the service API key|secrets
Add a purge command that deletes all takes|destructive
Update the production deployment workflow|deployment infrastructure
CASES
pass "each high-risk surface forces the comprehensive tier"

# --- risk wins over a fast-looking signal in the same sentence -----------------
# The failure this guards: a change described as a doc/copy tweak that also
# touches an auth path must NOT be talked down to fast by the doc wording.
got=$(tier_of "Fix a typo in the login authorization error copy")
[ "$got" = comprehensive ] || fail "risk+fast signal classed '$got', expected comprehensive (risk must win)"
got=$(tier_of "Adjust padding on the payment confirmation card")
[ "$got" = comprehensive ] || fail "styling on a payments surface classed '$got', expected comprehensive"
pass "a high-risk surface is never talked down by a fast-looking signal"

# --- genuinely narrow work reaches fast ---------------------------------------
for d in \
  "Fix a typo in the README" \
  "Adjust padding on the score card" \
  "Update the changelog wording"
do
  got=$(tier_of "$d")
  [ "$got" = fast ] || fail "narrow low-risk work classed '$got', expected fast: $d"
done
pass "documentation, copy, and isolated styling reach the fast tier"

# --- the check plans forbid what each tier must skip ---------------------------
fastplan=$("$TIER" checks fast)
assert_contains "$fastplan" "Do NOT run the full repository test suite" "fast plan must forbid the full suite"
assert_contains "$fastplan" "Do NOT run a device or browser matrix" "fast plan must forbid the matrix"
assert_contains "$fastplan" "Do NOT request or spawn an independent AI reviewer" "fast plan must forbid a reviewer"

stdplan=$("$TIER" checks standard)
assert_contains "$stdplan" "AFFECTED PACKAGE" "standard plan must scope lint to affected packages"
assert_contains "$stdplan" "AT MOST ONE relevant smoke test" "standard plan must cap smoke tests at one"
assert_contains "$stdplan" "Do NOT run the full repository test suite" "standard plan must forbid the full suite"
assert_contains "$stdplan" "Do NOT request or spawn a separate general reviewer" "standard plan must forbid a general reviewer"
assert_contains "$stdplan" "will run again on the same commit" "standard plan must forbid duplicating a CI check"

compplan=$("$TIER" checks comprehensive)
assert_contains "$compplan" "RELEVANT TO THE RISK SURFACE" "comprehensive plan must scope to the touched risk"
assert_contains "$compplan" "does NOT mean every device, every package" "comprehensive must not mean everything"
assert_contains "$compplan" "Never a generic" "comprehensive must forbid a generic review"
pass "each tier's check plan forbids what that tier is meant to skip"

# --- no tier authorizes an open-ended review ----------------------------------
for t in fast standard comprehensive; do
  plan=$("$TIER" checks "$t")
  case "$plan" in
    *"find anything wrong"*)
      # Only allowed as an explicit prohibition, never as an authorization.
      printf '%s' "$plan" | grep -q 'Never a generic "find anything wrong" review' \
        || fail "tier $t mentions a generic review without forbidding it"
      ;;
  esac
done
pass "no tier authorizes a generic find-anything-wrong review"

echo "fm-tier-lib.test.sh: all assertions passed"
