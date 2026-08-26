#!/usr/bin/env bash
# Guard for the shared-worktree teardown refusal (kunchenguid/firstmate#3075).
#
# The failure this prevents: a pool hands a slot to a NEW task while a
# finished-but-not-yet-torn-down task's meta still records that same path.
# Tearing down the finished task then hard-resets the slot, killing the live
# task's processes and discarding its uncommitted work. Upstream reported ~2.5
# hours of work lost to exactly this.
#
# The existing unlanded-work refusal cannot catch it: that check inspects THIS
# task's branch, and the work at risk belongs to a different task. So the test
# that matters is the ownership one - two metas naming one worktree must stop
# teardown before it touches anything, and must say which task it collided with.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot teardown-shared)
STATE="$TMP/state"
WT="$TMP/pool/slot1/repo"
OTHER="$TMP/pool/slot2/repo"
mkdir -p "$STATE" "$WT" "$OTHER"

# Two tasks, same recorded worktree - the reallocated-slot collision.
fm_write_meta "$STATE/task-a.meta" \
  "window=firstmate:fm-task-a" "endpoint_task_id=task-a" \
  "worktree=$WT" "project=$TMP/proj" "kind=ship" "mode=local-only"
fm_write_meta "$STATE/task-b.meta" \
  "window=firstmate:fm-task-b" "endpoint_task_id=task-b" \
  "worktree=$WT" "project=$TMP/proj" "kind=ship" "mode=local-only"

out="$TMP/out.txt"
rc=0
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$STATE" \
  "$ROOT/bin/fm-teardown.sh" task-a --force > "$out" 2>&1 || rc=$?

[ "$rc" -ne 0 ] || fail "teardown proceeded on a worktree another live task still records (#3075)"
assert_grep "task-b" "$out" "the refusal did not name the task it collided with"
assert_grep "ALSO recorded" "$out" "the refusal did not explain that the worktree is shared"
[ -e "$STATE/task-a.meta" ] || fail "the refusal erased task-a's durable record"
[ -e "$STATE/task-b.meta" ] || fail "the refusal erased the OTHER task's durable record"
[ -d "$WT" ] || fail "the refusal removed the shared worktree it was protecting"
pass "#3075: teardown refuses when another task's meta still records the same worktree"

# --force must NOT bypass it. Discard authority covers this task's own work; it
# was never authority to destroy a different task's.
assert_grep "Never bypass this with --force" "$out" \
  "the refusal did not state that --force is not an escape hatch here"
pass "#3075: --force does not bypass the shared-worktree refusal"

# The ordinary single-owner case must still tear down: a guard that refuses
# everything is not a guard.
rm -f "$STATE/task-b.meta"
fm_write_meta "$STATE/task-c.meta" \
  "window=firstmate:fm-task-c" "endpoint_task_id=task-c" \
  "worktree=$OTHER" "project=$TMP/proj" "kind=ship" "mode=local-only"
out2="$TMP/out2.txt"
# This case may still refuse for unrelated reasons (there is no real endpoint
# here); what must NOT appear is the shared-worktree refusal.
FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$STATE" \
  "$ROOT/bin/fm-teardown.sh" task-a --force > "$out2" 2>&1 || true
if grep -q "ALSO recorded" "$out2"; then
  fail "a distinct worktree was wrongly reported as shared (false positive)"
fi
pass "#3075: a task whose worktree no other meta records is not blocked by this guard"

echo "fm-teardown-shared-worktree.test.sh: all assertions passed"
