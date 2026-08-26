#!/usr/bin/env bash
# Validation-tier vocabulary for the `adaptive` delivery mode.
#
# This library is the SINGLE owner of what a validation tier is, which tiers
# exist, which risk surfaces force the strongest tier, and which checks each
# tier authorizes. bin/fm-brief.sh, bin/fm-spawn.sh, bin/fm-promote.sh and
# bin/fm-task-mode.sh consume it; none of them restate the tier set, and no
# generated brief invents a check list of its own.
#
# WHY A TIER AND NOT A FOURTH MODE: delivery mode answers "how does this land"
# (pipeline / PR / local branch). Tier answers "how much validation does this
# change earn". Those are orthogonal - a comprehensive-tier change can still
# land local-only, and a fast-tier change can still need a PR because the repo
# requires one. Collapsing them into one axis is what produced the measured
# behavior this library exists to fix: every task, however small, paying the
# same full-pipeline cost.
#
# MEASURED ORIGIN (see docs/adaptive-delivery.md for the full baseline): across
# twelve shipped firstmate ship-tasks on de-jish/iMeetStand, coding accounted
# for 1h23m of wall clock while the uniform AI review fix-loop accounted for
# 31h37m across 47 fix commits, and 76% of the agent-controlled critical path
# was idle waiting rather than work. Proportional validation targets the first
# number; the park/wedge repairs target the second.
#
# CLASSIFICATION IS FAIL-SAFE-UPWARD: an unrecognized or ambiguous task is
# `standard`, never `fast`. Any high-risk surface match forces `comprehensive`
# and no fast/standard signal can override it. That asymmetry is deliberate:
# misclassifying downward risks shipping an unvalidated auth change, while
# misclassifying upward only costs time.

# Closed set of validation tiers, strongest last.
FM_TIERS='fast standard comprehensive'

# Membership is tested against FM_TIERS so that variable is the one place the
# tier set is written; adding a tier here must not require editing a case arm.
fm_tier_validate() {  # <tier> [context-suffix]
  local tier=${1:-} context=${2:-} known list
  list=$(printf '%s' "$FM_TIERS" | tr ' ' ',')
  if [ -z "$tier" ]; then
    echo "error: --tier is required for mode=adaptive (one of: $list)${context:+ $context}" >&2
    return 1
  fi
  for known in $FM_TIERS; do
    [ "$tier" = "$known" ] && return 0
  done
  echo "error: --tier must be one of $list (got '$tier')${context:+ $context}" >&2
  return 1
}

# Rank a tier so callers can compare strength without duplicating the order.
fm_tier_rank() {  # <tier>
  case "${1:-}" in
    fast) printf '1' ;;
    standard) printf '2' ;;
    comprehensive) printf '3' ;;
    *) printf '0' ;;
  esac
}

# High-risk surfaces that force `comprehensive`, as one alternation per line so
# the list stays readable and greppable. These are the captain's stated
# high-risk surfaces: authentication/authorization, RLS and permission
# boundaries, privacy collection or disclosure, database migrations, payments,
# secrets, destructive operations, and deployment infrastructure.
fm_tier_risk_pattern() {
  cat <<'PAT'
auth|authn|authz|authenticat|authoriz|login|signin|sign-in|oauth|session token|jwt|bearer
rls|row.level.security|permission|privilege|access control|acl|policy boundary|tenant
privacy|pii|personal data|gdpr|ccpa|consent|telemetry|analytics collection|data retention
migration|schema change|alter table|drop table|drop column|backfill
payment|billing|invoice|subscription|stripe|checkout|refund
secret|credential|api key|private key|token rotation|vault|\.env
destructive|delete all|purge|truncate|hard reset|irreversible|data loss
deploy|deployment|infrastructure|terraform|kubernetes|helm|release pipeline|production config
PAT
}

# Signals that a change is genuinely small and low-risk.
fm_tier_fast_pattern() {
  cat <<'PAT'
typo|wording|copy change|copy edit|rename label|comment fix|docstring
documentation|readme|changelog|adr text|doc-only|docs only
styling|css|spacing|padding|margin|color token|font size|icon swap
tooltip|placeholder|aria-label|alt text
PAT
}

# Detect which high-risk surfaces a task description touches.
# Echoes one matched surface name per line; empty output means none matched.
fm_tier_matched_risks() {  # <text>
  local text lower
  text=${1:-}
  lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  local -a names=(authorization permission-boundary privacy migration payments secrets destructive deployment)
  local i=0 pat
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    if printf '%s' "$lower" | grep -qE "$pat"; then
      printf '%s\n' "${names[$i]}"
    fi
    i=$((i + 1))
  done < <(fm_tier_risk_pattern)
}

# Classify a task description into exactly one tier.
# Echoes "<tier>\t<reason>". Never errors on odd input: unknown work is
# `standard` by contract.
fm_tier_classify() {  # <text>
  local text lower risks fast_hit
  text=${1:-}
  lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')

  risks=$(fm_tier_matched_risks "$text" | paste -sd, - 2>/dev/null || true)
  if [ -n "$risks" ]; then
    printf 'comprehensive\ttouches a high-risk surface (%s)\n' "$risks"
    return 0
  fi

  fast_hit=''
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    if printf '%s' "$lower" | grep -qE "$pat"; then
      fast_hit=yes
      break
    fi
  done < <(fm_tier_fast_pattern)

  if [ -n "$fast_hit" ]; then
    printf 'fast\tnarrow low-risk surface (documentation, copy, or isolated styling) with no high-risk surface matched\n'
    return 0
  fi

  printf 'standard\tordinary product work with no high-risk surface matched\n'
}

# Emit the authorized check plan for a tier, one directive per line.
# A generated brief pastes this verbatim, so the wording here IS the contract
# the worker follows. Keep every line an instruction, not a description.
fm_tier_checks() {  # <tier>
  case "${1:-standard}" in
    fast)
      cat <<'PLAN'
- Run the SMALLEST relevant focused check for what you changed (a single test file, a single story, or a direct manual verification you describe in your status line). Nothing broader.
- Run changed-file lint or formatting if the project exposes it for individual files; skip it if the project only offers a whole-repo lint.
- Do NOT run the full repository test suite.
- Do NOT run a device or browser matrix.
- Do NOT request or spawn an independent AI reviewer.
- Do NOT open a pull request unless this project's own configuration requires one to run its checks; when no PR is required, stop at a clean committed branch.
PLAN
      ;;
    comprehensive)
      cat <<'PLAN'
- Run the focused tests for the changed behavior FIRST, and keep them green before widening.
- Run the checks that are RELEVANT TO THE RISK SURFACE THIS TASK ACTUALLY TOUCHES, and only those. Name the surface in your status line.
  - authorization or permission boundary -> the permission/policy test suite and any boundary assertion the repo already owns.
  - privacy -> the collection/disclosure assertions and any consent-path test.
  - migration -> forward AND rollback on a scratch database, plus the schema guard the repo already owns.
  - payments -> the payment-path suite and its idempotency/refund assertions.
  - secrets -> secret-scanning and the credential-path tests; never print a secret value.
  - destructive operation -> the guard tests that prove the operation refuses without authorization.
  - deployment infrastructure -> the deployment gate and post-deploy smoke, not the whole product suite.
- Run affected-package lint, type-check, and build.
- "Comprehensive" does NOT mean every device, every package, and every end-to-end test. Running unrelated suites is not thoroughness; it is cost with no signal. If you believe an unrelated suite is genuinely required, say why in your status line before running it.
- An independent reviewer is authorized ONLY for a precise review question you can state in one sentence, naming the risk surface. Never a generic "find anything wrong" review.
PLAN
      ;;
    *)
      cat <<'PLAN'
- Run the focused tests for the behavior you changed. Add a test for the behavior if an executable contract exists and none covers it.
- Run lint and type-check for the AFFECTED PACKAGE(S) only.
- Run the affected package's build when the change could plausibly break it (types, imports, bundling); skip it when it plainly cannot.
- Run AT MOST ONE relevant smoke test, chosen for the path you touched.
- Do NOT run the full repository test suite; the integration owner runs integration checks once.
- Do NOT request or spawn a separate general reviewer.
- Do NOT run a check locally that this project's CI will run again on the same commit, unless you state the reason in your status line (for example: the local run is the only place a secret-free fixture exists).
PLAN
      ;;
  esac
}

# One-line human summary a captain can read without opening the plan.
fm_tier_summary() {  # <tier>
  case "${1:-standard}" in
    fast) printf 'smallest focused check + changed-file lint; no reviewer, no full suite, no matrix' ;;
    comprehensive) printf 'focused tests + risk-surface checks + affected lint/type/build; scoped reviewer only for a named question' ;;
    *) printf 'focused tests + affected-package lint/type/build + at most one smoke test; no separate reviewer' ;;
  esac
}

# CLI surface so the classifier is testable and usable from a turn without
# sourcing. Guarded so sourcing stays side-effect free.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -euo pipefail
  case "${1:-}" in
    classify)
      shift
      fm_tier_classify "${*:-}"
      ;;
    checks)
      shift
      fm_tier_validate "${1:-}" || exit 2
      fm_tier_checks "$1"
      ;;
    summary)
      shift
      fm_tier_validate "${1:-}" || exit 2
      fm_tier_summary "$1"; echo
      ;;
    risks)
      shift
      fm_tier_matched_risks "${*:-}"
      ;;
    validate)
      shift
      fm_tier_validate "${1:-}" || exit 2
      ;;
    *)
      cat >&2 <<'USAGE'
usage: fm-tier-lib.sh <command> [args]

  classify <text...>   echo "<tier>\t<reason>" for a task description
  risks <text...>      list the high-risk surfaces the text matches
  checks <tier>        print the authorized check plan for a tier
  summary <tier>       print the one-line tier summary
  validate <tier>      exit 0 if the tier is in the closed set

Tiers: fast, standard, comprehensive. Unknown ordinary work is `standard`.
USAGE
      exit 2
      ;;
  esac
fi
