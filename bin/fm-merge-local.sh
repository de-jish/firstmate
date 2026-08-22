#!/usr/bin/env bash
# Guarded landing for an approved local-only task.
# Usage: fm-merge-local.sh <task-id> [--push]
#
# This is firstmate's local-only merge gate-action and the narrow sanctioned
# exception to hard rule 1's project-write ban.
# It runs only after the configured merge authority approves, or yolo=on owns a
# routine green landing within the accepted task contract.
# It never authorizes force, stash, reset, discard, or teardown of unlanded work.
#
# Without --push, this preserves local-only's historical behavior: fast-forward
# the project's checked-out local default branch and make no remote mutation.
# With --push, an origin remote is required and the same guarded landing is
# pushed directly to origin's default branch after the local fast-forward.
# Direct-main push is explicit because it skips pull-request-only checks and is
# an outward mutation beyond local-only's established no-push default.
# The command announces the exact local and remote mutation before it begins and
# names the skipped PR-check consequence on every --push use.
#
# Both paths refuse a dirty project checkout, a non-default checked-out branch,
# a missing task branch, and any task branch that is not a fast-forward of the
# relevant local default branch.
# The --push path fetches origin's default branch and additionally requires it
# to be an ancestor of the task branch, so a remote-main advance is refused
# before local main moves.
# Recovery is additive: the crewmate fetches origin, merges origin's exact
# default branch into fm/<task-id>, never rebases or forces, reruns validation,
# and reports ready before firstmate retries this gate-action.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

usage() {
  echo "usage: fm-merge-local.sh <task-id> [--push]" >&2
}

PUSH=0
ID=
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=1 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "error: unknown option: $arg" >&2; usage; exit 2 ;;
    *)
      [ -z "$ID" ] || { usage; exit 2; }
      ID=$arg
      ;;
  esac
done
[ -n "$ID" ] || { usage; exit 2; }

"$FM_ROOT/bin/fm-guard.sh" || true
META="$STATE/$ID.meta"
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }

PROJ=$(grep '^project=' "$META" | cut -d= -f2-)
MODE=$(grep '^mode=' "$META" | cut -d= -f2- || true)
[ "$MODE" = local-only ] || { echo "error: task $ID is mode=$MODE, not local-only; merge PR tasks with bin/fm-pr-merge.sh <id> <PR url> after approval" >&2; exit 1; }

default_branch() {
  local ref branch
  ref=$(git -C "$PROJ" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$ref" ]; then
    echo "${ref#origin/}"
    return 0
  fi
  for branch in main master; do
    if git -C "$PROJ" show-ref --verify --quiet "refs/heads/$branch"; then
      echo "$branch"
      return 0
    fi
  done
  return 1
}

BRANCH="fm/$ID"
git -C "$PROJ" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null || { echo "error: branch $BRANCH does not exist in $PROJ" >&2; exit 1; }

DEFAULT=$(default_branch) || { echo "error: cannot determine default branch for $PROJ; expected origin/HEAD, main, or master" >&2; exit 1; }

cur=$(git -C "$PROJ" symbolic-ref --short HEAD 2>/dev/null || echo "")
[ "$cur" = "$DEFAULT" ] || { echo "error: $PROJ is on '$cur', expected default branch '$DEFAULT'; cannot merge safely" >&2; exit 1; }
if [ -n "$(git -C "$PROJ" status --porcelain 2>/dev/null | head -1)" ]; then
  echo "error: $PROJ has a dirty working tree; refusing to merge into it" >&2
  exit 1
fi

if [ "$PUSH" -eq 1 ]; then
  git -C "$PROJ" remote get-url origin >/dev/null 2>&1 || {
    echo "error: --push requires an origin remote; local main was not changed" >&2
    exit 1
  }
  echo "CHECKING: fetch origin/$DEFAULT before any local or remote landing"
  git -C "$PROJ" fetch origin "$DEFAULT" >/dev/null || {
    echo "error: could not fetch origin/$DEFAULT; local main was not changed" >&2
    exit 1
  }
fi

recovery_ref=$DEFAULT
[ "$PUSH" -eq 0 ] || recovery_ref="origin/$DEFAULT"
if ! git -C "$PROJ" merge-base --is-ancestor "$DEFAULT" "$BRANCH" ||
  { [ "$PUSH" -eq 1 ] && ! git -C "$PROJ" merge-base --is-ancestor "origin/$DEFAULT" "$BRANCH"; }; then
  echo "REFUSED: $BRANCH is not a fast-forward of $recovery_ref (the default branch advanced or diverged)." >&2
  if [ "$PUSH" -eq 1 ]; then
    echo "Recovery: have the crewmate fetch origin and merge origin/$DEFAULT into $BRANCH additively; never rebase or force. Re-run validation, report ready, then retry." >&2
  else
    echo "Recovery: have the crewmate merge $DEFAULT into $BRANCH additively; never rebase or force. Re-run validation, report ready, then retry." >&2
  fi
  exit 1
fi

if [ "$PUSH" -eq 1 ]; then
  echo "ABOUT TO: fast-forward local $DEFAULT from $BRANCH and push $DEFAULT to origin"
  echo "SKIPPING: pull-request-only checks will not run; use this direct-main path only with the approved validation evidence"
else
  echo "ABOUT TO: fast-forward local $DEFAULT from $BRANCH; no remote will be changed"
fi

before=$(git -C "$PROJ" rev-parse --short "$DEFAULT")
git -C "$PROJ" merge --ff-only "$BRANCH" >/dev/null
after=$(git -C "$PROJ" rev-parse --short "$DEFAULT")

if [ "$PUSH" -eq 1 ]; then
  if ! git -C "$PROJ" push origin "refs/heads/$DEFAULT:refs/heads/$DEFAULT"; then
    echo "error: local $DEFAULT landed at $after, but the direct push to origin/$DEFAULT failed; do not force, reset, or discard anything" >&2
    exit 1
  fi
  echo "landed $BRANCH on local and origin/$DEFAULT ($before -> $after) in $PROJ"
else
  echo "landed $BRANCH on local $DEFAULT ($before -> $after) in $PROJ"
fi
