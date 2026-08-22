#!/usr/bin/env bash
# Change one live ship task's delivery mode and notify its worker with the
# canonical operational consequence.
# Usage: fm-task-mode.sh <task-id> <no-mistakes|direct-PR|local-only>
#
# The task's state/<id>.meta record is the durable current-mode authority.
# A successful transition rewrites its one mode= line atomically, appends a
# note: event to state/<id>.status, and sends the live worker one fixed steer
# through fm-send.sh.
# The original brief remains launch history; the steer explicitly supersedes
# its initial delivery section.
# If worker notification fails after the durable update, the command fails
# loudly while preserving the truthful new mode and names that partial result.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-gate-refuse-lib.sh
. "$SCRIPT_DIR/fm-gate-refuse-lib.sh"
# shellcheck source=bin/fm-delivery-mode-lib.sh
. "$SCRIPT_DIR/fm-delivery-mode-lib.sh"
# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"

fm_refuse_if_gate_agent

[ "$#" -eq 2 ] || {
  echo "usage: fm-task-mode.sh <task-id> <no-mistakes|direct-PR|local-only>" >&2
  exit 2
}
ID=$1
MODE=$2
fm_task_id_creation_valid "$ID" || { echo "error: invalid task id" >&2; exit 2; }
fm_delivery_mode_validate "$MODE"

"$SCRIPT_DIR/fm-guard.sh" || true
[ -d "$STATE" ] || { echo "error: state dir not found: $STATE" >&2; exit 1; }
META="$STATE/$ID.meta"
META_LOCK=$(fm_meta_lock_path "$META") || exit 1
META_LOCK_HELD=0
TMP=

task_mode_cleanup() {
  local status=$?
  [ -z "$TMP" ] || rm -f -- "$TMP" 2>/dev/null || true
  if [ "$META_LOCK_HELD" = 1 ]; then
    META_LOCK_HELD=0
    fm_lock_release "$META_LOCK" || true
  fi
  return "$status"
}
trap task_mode_cleanup EXIT

fm_lock_acquire_wait "$META_LOCK"
META_LOCK_HELD=1
[ -f "$META" ] || { echo "error: no meta for task $ID at $META" >&2; exit 1; }
grep -qx 'kind=ship' "$META" || { echo "error: task $ID is not a ship task" >&2; exit 1; }
[ "$(grep -c '^mode=' "$META")" -eq 1 ] || { echo "error: task $ID metadata must contain exactly one mode= record" >&2; exit 1; }
OLD_MODE=$(sed -n 's/^mode=//p' "$META")
fm_delivery_mode_validate "$OLD_MODE"

if [ "$OLD_MODE" = "$MODE" ]; then
  fm_lock_release "$META_LOCK"
  META_LOCK_HELD=0
  echo "task $ID delivery mode is already $MODE; nothing changed"
  exit 0
fi

TMP="$STATE/.$ID.meta.mode.${BASHPID:-$$}"
grep -v '^mode=' "$META" > "$TMP"
printf 'mode=%s\n' "$MODE" >> "$TMP"
mv "$TMP" "$META"
TMP=
fm_lock_release "$META_LOCK"
META_LOCK_HELD=0

printf 'note: delivery mode changed from %s to %s by bin/fm-task-mode.sh\n' "$OLD_MODE" "$MODE" >> "$STATE/$ID.status"

case "$MODE" in
  local-only)
    CONSEQUENCE="Stop after a clean commit on fm/$ID; do not push, open a PR, merge, or run no-mistakes. If the default branch advanced, fetch origin and merge its default branch additively into fm/$ID; never rebase or force. Re-run validation, then report done: ready in branch fm/$ID."
    ;;
  direct-PR)
    CONSEQUENCE="After a clean commit on fm/$ID, push only that branch and open a PR with gh-axi; do not run no-mistakes and never merge the PR. Report done with the full PR URL."
    ;;
  no-mistakes)
    CONSEQUENCE="After a clean commit on fm/$ID, report done and wait for firstmate to invoke the no-mistakes validation path; do not push or open a PR yourself and never merge a PR."
    ;;
esac
MESSAGE="Delivery mode changed from $OLD_MODE to $MODE and is recorded in task metadata. This supersedes the initial delivery section in your brief. $CONSEQUENCE"
if ! FM_HOME="$FM_HOME" "$FM_ROOT/bin/fm-send.sh" "$ID" "$MESSAGE"; then
  echo "error: changed task $ID delivery mode from $OLD_MODE to $MODE and recorded it, but worker notification failed; inspect the endpoint before retrying any steer" >&2
  exit 1
fi

echo "changed task $ID delivery mode from $OLD_MODE to $MODE and notified the worker"
