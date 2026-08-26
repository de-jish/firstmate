#!/usr/bin/env bash
# Lightweight, local, append-only task timing instrumentation.
#
# WHY THIS EXISTS: reconstructing where a task's wall clock actually went
# required mining git author dates, GitHub Actions runs, and file mtimes, and
# even then three stages could not be measured at all (worker spawn latency,
# per-stage validation split, captain notification delay) because nothing
# recorded them. This script records them at the moment they happen so the next
# baseline is a read rather than an archaeology exercise.
#
# Usage:
#   fm-timing.sh record <task-id> <event> [detail]   append one event
#   fm-timing.sh summary [task-id]                   critical path + work/wait split
#   fm-timing.sh events <task-id>                    raw events for one task
#   fm-timing.sh retire <task-id>                    drop one task's rows
#   fm-timing.sh events-help                         the event vocabulary
#
# PRIVACY: a record carries a task id, an event name, and an optional short
# detail token. It never carries file contents, diffs, prompts, branch content,
# or captain text. `detail` is truncated and stripped of tabs/newlines so a
# caller cannot smuggle a payload into the log. Nothing leaves this machine.
#
# COST: `record` is one line appended to one file. With FM_TIMING=off it returns
# immediately without touching disk. It NEVER fails its caller - a broken
# instrument must not break a delivery - so every path exits 0.
#
# CLOCKS: the ordering key is the wall-clock epoch, because that is the only
# clock shared across the separate processes (firstmate turn, worker, watcher)
# that write here. A monotonic seconds-since-boot reading is recorded beside it
# so a backward wall-clock step (NTP correction, timezone change, suspend) is
# DETECTABLE rather than silently producing a negative or inflated duration:
# `summary` refuses to score an interval whose two clocks disagree and says so.
# This is deliberately not a claim that a cross-process monotonic clock exists.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-$FM_ROOT}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
LOG="${FM_TIMING_LOG:-$STATE/timing.log}"

# Seconds since boot, for clock-jump detection. One fork per process, cached.
FM_TIMING_BOOT=
fm_timing_mono() {
  local now up boot
  if [ -r /proc/uptime ]; then
    read -r up _ < /proc/uptime 2>/dev/null || up=0
    printf '%s' "${up%%.*}"
    return 0
  fi
  if [ -z "$FM_TIMING_BOOT" ]; then
    boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/.*sec = \([0-9]*\).*/\1/p')
    FM_TIMING_BOOT=${boot:-0}
  fi
  [ "$FM_TIMING_BOOT" != 0 ] || { printf '0'; return 0; }
  now=${EPOCHSECONDS:-$(date +%s)}
  printf '%s' "$(( now - FM_TIMING_BOOT ))"
}

# The event vocabulary. Each row is: <event> <class> <meaning>.
# `class` drives the work/wait split in `summary`, applied to the interval that
# the event OPENS. `boundary` events open nothing (they close the task).
fm_timing_vocab() {
  cat <<'VOCAB'
intake work the request arrived and firstmate began resolving it
planned work planning/classification finished; the tier and dispatch shape are decided
worker-requested wait a worker spawn was issued; the interval is startup latency
worker-started work the worker acknowledged its brief and began
impl-complete work implementation is committed; validation may begin
validate-start work a validation stage began (detail = stage name)
validate-end work a validation stage ended (detail = stage name)
repair-start work the one authorized repair attempt began
repair-end work the repair attempt ended
ci-wait-start wait pushed and waiting on remote CI
ci-wait-end work remote CI returned
captain-notified wait the captain was told; waiting on a human decision
blocked wait the task is waiting on firstmate or a decision
resumed work the wait cleared and work continued
complete boundary the task landed and is closed
VOCAB
}

fm_timing_class() {  # <event> -> work|wait|boundary|unknown
  local e=${1:-} name cls
  while read -r name cls _; do
    [ "$name" = "$e" ] && { printf '%s' "$cls"; return 0; }
  done < <(fm_timing_vocab)
  printf 'unknown'
}

fm_timing_record() {  # <task-id> <event> [detail]
  case "${FM_TIMING:-on}" in off|0|false) return 0 ;; esac
  local task=${1:-} event=${2:-} detail=${3:-} now mono
  [ -n "$task" ] && [ -n "$event" ] || return 0
  # Strip anything that could break the record format or carry a payload.
  task=$(printf '%s' "$task" | tr -d '\t\n' | cut -c1-64)
  event=$(printf '%s' "$event" | tr -d '\t\n' | cut -c1-32)
  detail=$(printf '%s' "$detail" | tr -d '\t\n' | cut -c1-64)
  now=${EPOCHSECONDS:-$(date +%s 2>/dev/null || echo 0)}
  mono=$(fm_timing_mono 2>/dev/null || echo 0)
  # Never create the log's directory. Timing is best-effort telemetry, and the
  # last thing it records is a task's terminal boundary - which for a secondmate
  # runs AFTER teardown removed that home, with STATE still pointing inside it.
  # A `mkdir -p` here quietly resurrected the retired home, so teardown reported
  # success while the directory it had just deleted was back on disk. Skipping
  # the record instead keeps this from ever putting state back.
  [ -d "$(dirname "$LOG")" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$now" "$mono" "$task" "$event" "$detail" >> "$LOG" 2>/dev/null || true
  return 0
}

fm_timing_summary() {  # [task-id]
  local only=${1:-}
  [ -s "$LOG" ] || { echo "no timing data recorded yet ($LOG)"; return 0; }
  FM_TIMING_ONLY="$only" FM_TIMING_VOCAB="$(fm_timing_vocab)" awk -F'\t' '
    function hm(s,   sg) {
      if (s == "") return "n/a"
      sg = ""; if (s < 0) { sg = "-"; s = -s }
      if (s >= 3600) return sprintf("%s%dh%02dm", sg, int(s/3600), int((s%3600)/60))
      if (s >= 60)   return sprintf("%s%dm%02ds", sg, int(s/60), s%60)
      return sprintf("%s%ds", sg, s)
    }
    BEGIN {
      only = ENVIRON["FM_TIMING_ONLY"]
      nv = split(ENVIRON["FM_TIMING_VOCAB"], vlines, "\n")
      for (v = 1; v <= nv; v++) {
        if (vlines[v] == "") continue
        split(vlines[v], f, " "); cls[f[1]] = f[2]
      }
    }
    {
      if (only != "" && $3 != only) next
      t = $3
      if (!(t in seen)) { seen[t] = 1; order[++n] = t; first[t] = $1 }
      last[t] = $1
      # Close the previous interval for this task.
      if (t in pending) {
        d = $1 - pending_wall[t]
        md = $2 - pending_mono[t]
        # Both clocks must agree within 2s or the interval is untrusted.
        if (d < 0 || (pending_mono[t] > 0 && $2 > 0 && (d - md > 2 || md - d > 2))) {
          untrusted[t]++
        } else {
          c = cls[pending[t]]; if (c == "") c = "unknown"
          bucket[t, c] += d
          stage[t, pending[t]] += d
          if (d > longest_d[t]) { longest_d[t] = d; longest_e[t] = pending[t] }
        }
      }
      pending[t] = $4; pending_wall[t] = $1; pending_mono[t] = $2
      if ($4 == "complete") delete pending[t]
    }
    END {
      printf "%-30s %10s %10s %10s %9s  %s\n", "task", "total", "work", "waiting", "wait%", "longest single wait"
      printf "%s\n", "----------------------------------------------------------------------------------------------------"
      for (i = 1; i <= n; i++) {
        t = order[i]
        w = bucket[t, "work"] + 0; q = bucket[t, "wait"] + 0
        tot = last[t] - first[t]
        pct = (w + q) > 0 ? sprintf("%.0f%%", 100 * q / (w + q)) : "-"
        note = longest_e[t] == "" ? "-" : sprintf("%s (%s)", longest_e[t], hm(longest_d[t]))
        printf "%-30s %10s %10s %10s %9s  %s\n", substr(t,1,30), hm(tot), hm(w), hm(q), pct, note
        if (untrusted[t] > 0) printf "%-30s %s\n", "", "  ! " untrusted[t] " interval(s) skipped: wall and monotonic clocks disagreed"
        TW += w; TQ += q; TT += tot
      }
      printf "%s\n", "----------------------------------------------------------------------------------------------------"
      pct = (TW + TQ) > 0 ? sprintf("%.0f%%", 100 * TQ / (TW + TQ)) : "-"
      printf "%-30s %10s %10s %10s %9s\n", "TOTAL (" n " task(s))", hm(TT), hm(TW), hm(TQ), pct
      printf "\ncritical path = total; work = productive intervals; waiting = spawn latency, CI waits, and decision waits.\n"
    }
  ' "$LOG"
}

case "${1:-}" in
  record)  shift; fm_timing_record "$@" ;;
  summary) shift; fm_timing_summary "${1:-}" ;;
  events)
    shift
    [ -s "$LOG" ] || { echo "no timing data recorded yet ($LOG)"; exit 0; }
    # strftime is a gawk extension and is absent from the BSD awk on macOS, so
    # the human-readable stamp is rendered with date(1) in whichever dialect the
    # platform provides.
    fm_when() {
      date -r "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || printf '%s' "$1"
    }
    printf '%-12s %-21s %-18s %s\n' 'epoch' 'when' 'event' 'detail'
    only=${1:-}
    while IFS=$'\t' read -r ep _mono task ev detail; do
      [ -z "$only" ] || [ "$task" = "$only" ] || continue
      printf '%-12s %-21s %-18s %s\n' "$ep" "$(fm_when "$ep")" "$ev" "$detail"
    done < "$LOG"
    ;;
  retire)
    shift
    task=${1:-}
    [ -n "$task" ] || { echo "usage: fm-timing.sh retire <task-id>" >&2; exit 2; }
    [ -s "$LOG" ] || exit 0
    tmp="$LOG.tmp.$$"
    awk -F'\t' -v t="$task" '$3!=t' "$LOG" > "$tmp" 2>/dev/null && mv "$tmp" "$LOG"
    ;;
  events-help)
    printf '%-18s %-9s %s\n' EVENT CLASS MEANING
    fm_timing_vocab | while read -r e c rest; do printf '%-18s %-9s %s\n' "$e" "$c" "$rest"; done
    ;;
  -h|--help|'')
    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "error: unknown command '${1}'; try --help" >&2; exit 2 ;;
esac
