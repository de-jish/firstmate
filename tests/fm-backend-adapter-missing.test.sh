#!/usr/bin/env bash
# Regression guard: a missing or unreadable backend adapter must be an ordinary
# error, never a shell abort.
#
# THE DEFECT. `fm_backend_source` sourced its adapter with
#   . "$FM_BACKEND_LIB_DIR/backends/<name>.sh" || return 1
# but under `set -e` on bash 3.2 (the system bash on macOS), `.` on a missing
# file is a FATAL error that terminates the shell immediately. The `|| return 1`
# never ran, so every caller's error handling was bypassed - including
# bin/fm-teardown.sh's required herdr preflight, which is written to refuse
# loudly. Instead its whole process was aborted, and because the EXIT trap
# observed status 0, teardown REPORTED SUCCESS while having done nothing and
# having refused nothing. A caller reading that exit code would believe the task
# was cleaned up.
#
# THE FIX. Prove the adapter is readable before sourcing it, so the failure is a
# plain `return 1` on every bash version and each caller's own contract applies
# again.
#
# WHAT MUST NOT CHANGE. The three liveness readers below deliberately degrade to
# `unknown`/`unverified` when a backend cannot answer, and callers depend on
# that (the watcher uses `unknown` as its cue for pane-tail detection). This
# guard asserts they STILL degrade - the fix only ensures they are reached at
# all, instead of the shell dying first.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot backend-adapter)

# A copy of bin/ with the herdr adapter removed.
ROOTCOPY="$TMP/root"
mkdir -p "$ROOTCOPY"
cp -R "$ROOT/bin" "$ROOTCOPY/bin"
rm -f "$ROOTCOPY/bin/backends/herdr.sh"
[ ! -e "$ROOTCOPY/bin/backends/herdr.sh" ] || fail "fixture setup: adapter still present"

# --- the shell survives, and the error propagates ------------------------------
# Run under `set -e`, which is the condition that made this fatal.
out=$(bash -c '
  set -eu
  . "'"$ROOTCOPY"'/bin/fm-backend.sh"
  if fm_backend_source herdr 2>/dev/null; then
    echo "SOURCED"
  else
    echo "RETURNED_NONZERO"
  fi
  echo "SHELL_SURVIVED"
' 2>&1) || true
assert_contains "$out" "RETURNED_NONZERO" "a missing adapter did not return a plain non-zero status"
assert_contains "$out" "SHELL_SURVIVED" "a missing adapter aborted the shell instead of returning"
pass "a missing adapter returns non-zero and the shell survives under set -e"

# The refusal must name the adapter, or an operator cannot act on it.
err=$(bash -c '
  set -eu
  . "'"$ROOTCOPY"'/bin/fm-backend.sh"
  fm_backend_source herdr || true
' 2>&1) || true
assert_contains "$err" "backends/herdr.sh" "the refusal did not name the adapter path"
pass "the refusal names the missing adapter"

# --- an unreadable (present but chmod 000) adapter behaves identically ---------
ROOTCOPY2="$TMP/root2"
mkdir -p "$ROOTCOPY2"
cp -R "$ROOT/bin" "$ROOTCOPY2/bin"
chmod 000 "$ROOTCOPY2/bin/backends/herdr.sh"
if [ -r "$ROOTCOPY2/bin/backends/herdr.sh" ]; then
  # Running as a user that bypasses the permission bit (e.g. root); skip rather
  # than assert something the environment cannot demonstrate.
  pass "unreadable-adapter case skipped: this user can read a mode-000 file"
else
  out=$(bash -c '
    set -eu
    . "'"$ROOTCOPY2"'/bin/fm-backend.sh"
    fm_backend_source herdr 2>/dev/null || echo "RETURNED_NONZERO"
    echo "SHELL_SURVIVED"
  ' 2>&1) || true
  assert_contains "$out" "RETURNED_NONZERO" "an unreadable adapter did not return non-zero"
  assert_contains "$out" "SHELL_SURVIVED" "an unreadable adapter aborted the shell"
  pass "an unreadable adapter is treated the same as a missing one"
fi
chmod 644 "$ROOTCOPY2/bin/backends/herdr.sh" 2>/dev/null || true

# --- all three degrade-to-unknown sites still degrade, and are REACHED ---------
# These are the sites that swallow a source failure on purpose. Each must return
# 0 with its documented degraded answer, and must not take the shell down.
check_site() {  # <function> <expected-output>
  local fn=$1 want=$2 got
  got=$(bash -c '
    set -eu
    . "'"$ROOTCOPY"'/bin/fm-backend.sh"
    '"$fn"' herdr default:wG:pQ 2>/dev/null
    printf "|rc=%s" "$?"
  ' 2>&1) || true
  case "$got" in
    "$want|rc=0") ;;
    *) fail "$fn on a missing adapter gave '$got', expected '$want|rc=0'" ;;
  esac
}
check_site fm_backend_busy_state unknown
check_site fm_backend_composer_state unknown
check_site fm_backend_agent_state unverified
pass "all three liveness readers still degrade to their documented answer and are reached"

# --- a working adapter is unaffected -------------------------------------------
got=$(bash -c '
  set -eu
  . "'"$ROOT"'/bin/fm-backend.sh"
  fm_backend_source tmux && echo OK
' 2>&1) || true
assert_contains "$got" "OK" "a present adapter no longer sources"
pass "a present adapter still sources normally"

# --- teardown refuses, and preserves the worktree and unlanded work ------------
# The destructive path must reach its own refusal rather than aborting, and
# nothing may be touched on the way out.
CASE="$TMP/case"
mkdir -p "$CASE/state" "$CASE/config" "$CASE/fakebin"
fm_git_identity
git init -q "$CASE/project"
git -C "$CASE/project" commit -q --allow-empty -m base
git -C "$CASE/project" worktree add -q -b fm/task-x1 "$CASE/wt" >/dev/null 2>&1
# Unlanded work: a commit that exists nowhere else, plus an uncommitted file.
echo "unlanded" > "$CASE/wt/work.txt"
git -C "$CASE/wt" add work.txt
git -C "$CASE/wt" commit -q -m "unlanded work"
UNLANDED_SHA=$(git -C "$CASE/wt" rev-parse HEAD)
echo "uncommitted" > "$CASE/wt/dirty.txt"

for tool in treehouse tmux herdr gh-axi; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CASE/fakebin/$tool"
  chmod +x "$CASE/fakebin/$tool"
done

fm_write_meta "$CASE/state/task-x1.meta" \
  "window=default:wG:pQ" "endpoint_task_id=task-x1" \
  "worktree=$CASE/wt" "project=$CASE/project" "kind=ship" "mode=local-only"
printf '%s\n' 'backend=herdr' 'herdr_session=default' 'herdr_workspace_id=wG' \
  'herdr_tab_id=wG:tQ' 'herdr_pane_id=wG:pQ' >> "$CASE/state/task-x1.meta"
: > "$CASE/state/task-x1.status"

rc=0
# --force deliberately: it bypasses the unlanded-work refusal, so what is under
# test here is the ADAPTER refusal, not the landed-work check.
PATH="$CASE/fakebin:$PATH" FM_ROOT_OVERRIDE="$ROOTCOPY" FM_STATE_OVERRIDE="$CASE/state" \
  FM_CONFIG_OVERRIDE="$CASE/config" \
  "$ROOTCOPY/bin/fm-teardown.sh" task-x1 --force > "$CASE/out" 2>&1 || rc=$?

[ "$rc" -ne 0 ] \
  || fail "teardown reported SUCCESS on a missing adapter; a caller would believe the task was cleaned up"
[ -d "$CASE/wt" ] || fail "the refusal removed the isolated copy"
[ -f "$CASE/wt/dirty.txt" ] || fail "the refusal discarded uncommitted work"
[ "$(git -C "$CASE/wt" rev-parse HEAD 2>/dev/null)" = "$UNLANDED_SHA" ] \
  || fail "the refusal moved or discarded the unlanded commit"
[ "$(git -C "$CASE/wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "fm/task-x1" ] \
  || fail "the refusal dropped the task branch"
[ -e "$CASE/state/task-x1.meta" ] || fail "the refusal erased the durable endpoint metadata"
[ -e "$CASE/state/task-x1.status" ] || fail "the refusal erased the task status record"
pass "SAFETY: on ambiguous backend state teardown refuses and preserves the worktree, unlanded work, and records"

echo "fm-backend-adapter-missing.test.sh: all assertions passed"
