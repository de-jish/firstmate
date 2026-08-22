#!/usr/bin/env bash
# Regression for the local-only landing path and live task delivery-mode changes.
# The 2026-08-22 incident had two observable failures: fm-merge-local stopped
# after moving local main, and firstmate had to hand-write mode-change steers
# while state/<id>.meta continued to record the obsolete mode.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MERGE_LOCAL="$ROOT/bin/fm-merge-local.sh"
TASK_MODE="$ROOT/bin/fm-task-mode.sh"
TMP_ROOT=$(fm_test_tmproot fm-local-delivery)

make_project() {  # <name>
  local name=$1 project remote home
  project="$TMP_ROOT/$name/project"
  remote="$TMP_ROOT/$name/origin.git"
  home="$TMP_ROOT/$name/home"
  mkdir -p "$project" "$home/state"
  git -C "$project" init -q -b main
  printf 'base\n' > "$project/base.txt"
  git -C "$project" add base.txt
  git -C "$project" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm base
  git clone --quiet --bare "$project" "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  git -C "$project" remote add origin "file://$remote"
  git -C "$project" fetch -q origin
  printf '%s|%s|%s\n' "$project" "$remote" "$home"
}

add_task_commit() {  # <project> <id>
  local project=$1 id=$2
  git -C "$project" checkout -qb "fm/$id"
  printf '%s\n' "$id" > "$project/$id.txt"
  git -C "$project" add "$id.txt"
  git -C "$project" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm "$id"
  git -C "$project" checkout -q main
}

write_task_meta() {  # <home> <id> <project> <mode>
  local home=$1 id=$2 project=$3 mode=$4
  fm_write_meta "$home/state/$id.meta" \
    "window=fm-$id" \
    "worktree=$project" \
    "project=$project" \
    "harness=codex" \
    "kind=ship" \
    "mode=$mode" \
    "yolo=off"
}

test_branch_behind_main_is_refused_with_additive_recovery() {
  local rec project remote home id=behind-main-a1 out status remote_before remote_after
  rec=$(make_project behind)
  IFS='|' read -r project remote home <<EOF
$rec
EOF
  add_task_commit "$project" "$id"
  printf 'main advanced\n' > "$project/main.txt"
  git -C "$project" add main.txt
  git -C "$project" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm 'advance main'
  git -C "$project" push -q origin main
  write_task_meta "$home" "$id" "$project" local-only
  remote_before=$(git --git-dir="$remote" rev-parse main)

  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$MERGE_LOCAL" "$id" --push 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a local-only branch behind main was landed"
  assert_contains "$out" "fetch origin and merge origin/main into fm/$id additively" \
    "the refusal did not name the deterministic additive recovery"
  assert_contains "$out" "never rebase or force" \
    "the refusal did not preserve the no-rebase/no-force contract"
  assert_not_contains "$out" "rebase fm/$id" \
    "the refusal retained the incident's incorrect rebase advice"
  remote_after=$(git --git-dir="$remote" rev-parse main)
  [ "$remote_after" = "$remote_before" ] || fail "the refused landing changed remote main"
  pass "fm-merge-local: a branch behind main stays refused with exact additive recovery"
}

test_push_landing_updates_remote_and_warns_before_mutation() {
  local rec project remote home id=push-main-b1 out status task_head remote_head
  rec=$(make_project push)
  IFS='|' read -r project remote home <<EOF
$rec
EOF
  add_task_commit "$project" "$id"
  write_task_meta "$home" "$id" "$project" local-only
  task_head=$(git -C "$project" rev-parse "fm/$id")

  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$MERGE_LOCAL" "$id" --push 2>&1)
  status=$?
  expect_code 0 "$status" "push landing"
  remote_head=$(git --git-dir="$remote" rev-parse main)
  [ "$remote_head" = "$task_head" ] || fail "the successful push landing did not update remote main"
  assert_contains "$out" "ABOUT TO: fast-forward local main from fm/$id and push main to origin" \
    "the command did not announce its local and remote mutations before landing"
  assert_contains "$out" "SKIPPING: pull-request-only checks will not run" \
    "the direct-main path hid the checks it skips"
  [ "$(git -C "$project" rev-parse main)" = "$task_head" ] || fail "the successful push landing did not update local main"
  pass "fm-merge-local: --push lands the task on local and remote main with an informed warning"
}

test_plain_landing_preserves_the_no_push_default() {
  local rec project remote home id=local-main-b2 out status task_head remote_before remote_after
  rec=$(make_project local)
  IFS='|' read -r project remote home <<EOF
$rec
EOF
  add_task_commit "$project" "$id"
  write_task_meta "$home" "$id" "$project" local-only
  task_head=$(git -C "$project" rev-parse "fm/$id")
  remote_before=$(git --git-dir="$remote" rev-parse main)

  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$MERGE_LOCAL" "$id" 2>&1)
  status=$?
  expect_code 0 "$status" "plain local landing"
  assert_contains "$out" "ABOUT TO: fast-forward local main from fm/$id; no remote will be changed" \
    "the default path did not announce its local-only mutation"
  assert_not_contains "$out" "SKIPPING: pull-request-only checks" \
    "the local-only path printed the direct-push consequence without a direct push"
  remote_after=$(git --git-dir="$remote" rev-parse main)
  [ "$remote_after" = "$remote_before" ] || fail "the plain landing unexpectedly pushed remote main"
  [ "$(git -C "$project" rev-parse main)" = "$task_head" ] || fail "the plain landing did not update local main"
  pass "fm-merge-local: direct push stays opt-in and plain landing remains local"
}

test_live_mode_change_records_and_notifies() {
  local home fake_root send_log id=mode-change-c1 out status
  home="$TMP_ROOT/mode/home"
  fake_root="$TMP_ROOT/mode/fake-root"
  send_log="$TMP_ROOT/mode/send.log"
  mkdir -p "$home/state" "$home/data/$id" "$fake_root/bin"
  fm_write_meta "$home/state/$id.meta" \
    "window=fm-$id" \
    "worktree=/tmp/task" \
    "project=/tmp/project" \
    "harness=codex" \
    "kind=ship" \
    "mode=no-mistakes" \
    "yolo=off"
  printf 'Delivery contract: mode=no-mistakes\n' > "$home/data/$id/brief.md"
  cat > "$fake_root/bin/fm-send.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FM_TEST_SEND_LOG"
SH
  chmod +x "$fake_root/bin/fm-send.sh"

  out=$(FM_ROOT_OVERRIDE="$fake_root" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_DATA_OVERRIDE="$home/data" FM_TEST_SEND_LOG="$send_log" "$TASK_MODE" "$id" local-only 2>&1)
  status=$?
  expect_code 0 "$status" "live delivery-mode change"
  [ "$(grep -c '^mode=' "$home/state/$id.meta")" = 1 ] || fail "the mode change left duplicate mode records"
  assert_grep 'mode=local-only' "$home/state/$id.meta" "the mode change did not update task metadata"
  assert_grep 'note: delivery mode changed from no-mistakes to local-only' "$home/state/$id.status" \
    "the mode change did not append a durable status record"
  assert_grep "Delivery mode changed from no-mistakes to local-only" "$send_log" \
    "the mode change did not notify the live worker with a canonical steer"
  assert_grep "do not push, open a PR, merge, or run no-mistakes" "$send_log" \
    "the canonical local-only steer omitted its operational consequence"
  assert_contains "$out" "changed task $id delivery mode from no-mistakes to local-only" \
    "the command did not report the recorded transition"
  pass "fm-task-mode: one command records a live mode change and sends its canonical steer"
}

test_gate_agent_cannot_change_a_live_mode() {
  local home fake_root send_log id=gate-mode-d1 out status
  home="$TMP_ROOT/gate-mode/home"
  fake_root="$TMP_ROOT/gate-mode/fake-root"
  send_log="$TMP_ROOT/gate-mode/send.log"
  mkdir -p "$home/state" "$fake_root/bin"
  fm_write_meta "$home/state/$id.meta" \
    "window=fm-$id" \
    "worktree=/tmp/task" \
    "project=/tmp/project" \
    "harness=codex" \
    "kind=ship" \
    "mode=no-mistakes" \
    "yolo=off"
  cat > "$fake_root/bin/fm-send.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' sent > "$FM_TEST_SEND_LOG"
SH
  chmod +x "$fake_root/bin/fm-send.sh"

  out=$(NO_MISTAKES_GATE=1 FM_GATE_REFUSE_BYPASS='' FM_ROOT_OVERRIDE="$fake_root" \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_TEST_SEND_LOG="$send_log" \
    "$TASK_MODE" "$id" local-only 2>&1)
  status=$?
  expect_code 3 "$status" "gate-agent live delivery-mode change"
  assert_contains "$out" "NO_MISTAKES_GATE set" "the gate-agent refusal did not name its authority boundary"
  assert_grep 'mode=no-mistakes' "$home/state/$id.meta" "the refused gate action changed task metadata"
  assert_absent "$home/state/$id.status" "the refused gate action wrote a status event"
  assert_absent "$send_log" "the refused gate action notified the worker"
  pass "fm-task-mode: a no-mistakes gate agent cannot mutate or notify a live task"
}

test_push_without_an_origin_refuses_before_touching_local_main() {
  local project home id=no-origin-b3 out status main_before
  project="$TMP_ROOT/no-origin/project"
  home="$TMP_ROOT/no-origin/home"
  mkdir -p "$project" "$home/state"
  git -C "$project" init -q -b main
  printf 'base\n' > "$project/base.txt"
  git -C "$project" add base.txt
  git -C "$project" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm base
  add_task_commit "$project" "$id"
  write_task_meta "$home" "$id" "$project" local-only
  main_before=$(git -C "$project" rev-parse main)

  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$MERGE_LOCAL" "$id" --push 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "--push succeeded on a project with no origin remote"
  assert_contains "$out" "--push requires an origin remote" \
    "the remoteless refusal did not name the missing origin"
  [ "$(git -C "$project" rev-parse main)" = "$main_before" ] || \
    fail "the refused --push still moved local main"
  assert_contains "$out" "local main was not changed" \
    "the remoteless refusal did not state that local main is untouched"
  pass "fm-merge-local: --push on a remoteless project refuses before any local mutation"
}

test_rejected_push_reports_the_partial_landing_without_rewriting_history() {
  local rec project remote home id=push-rejected-b4 out status task_head remote_before
  rec=$(make_project rejected)
  IFS='|' read -r project remote home <<EOF
$rec
EOF
  add_task_commit "$project" "$id"
  write_task_meta "$home" "$id" "$project" local-only
  task_head=$(git -C "$project" rev-parse "fm/$id")
  remote_before=$(git --git-dir="$remote" rev-parse main)
  # Stand in for a protected default branch: origin rejects every push to main.
  printf '#!/bin/sh\nexit 1\n' > "$remote/hooks/pre-receive"
  chmod +x "$remote/hooks/pre-receive"

  out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$MERGE_LOCAL" "$id" --push 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "a rejected direct push was reported as a successful landing"
  assert_contains "$out" "the direct push to origin/main failed" \
    "the rejected push did not name the failed remote landing"
  assert_contains "$out" "do not force, reset, or discard anything" \
    "the rejected push did not preserve the no-force recovery contract"
  [ "$(git --git-dir="$remote" rev-parse main)" = "$remote_before" ] || \
    fail "a rejected push still moved remote main"
  [ "$(git -C "$project" rev-parse main)" = "$task_head" ] || \
    fail "the reported local landing did not actually happen"
  [ "$(git -C "$project" rev-parse "fm/$id")" = "$task_head" ] || \
    fail "the failed push rewrote the unlanded task branch"
  pass "fm-merge-local: a rejected direct push reports the partial landing and rewrites nothing"
}

test_push_landing_updates_remote_and_warns_before_mutation
test_plain_landing_preserves_the_no_push_default
test_push_without_an_origin_refuses_before_touching_local_main
test_rejected_push_reports_the_partial_landing_without_rewriting_history
test_branch_behind_main_is_refused_with_additive_recovery
test_live_mode_change_records_and_notifies
test_gate_agent_cannot_change_a_live_mode
echo "# all local delivery tests passed"
