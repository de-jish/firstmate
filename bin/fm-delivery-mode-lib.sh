#!/usr/bin/env bash
# Shared closed-set validation for per-task ship delivery modes.
# bin/fm-spawn.sh owns the requirement that every ship task carries a concrete
# mode; this library lets brief creation, promotion, and live mode changes use
# that exact accepted set without restating it.

fm_delivery_mode_validate() {  # <mode> [context-suffix]
  local mode=${1:-} context=${2:-}
  case "$mode" in
    no-mistakes|direct-PR|local-only) return 0 ;;
    no-mistakes-prod-only)
      echo "error: no-mistakes-prod-only is a registry policy, not a task mode; classify this task's surface and resolve it to no-mistakes or direct-PR${context:+ $context}" >&2
      return 1
      ;;
    *)
      echo "error: --mode must be one of no-mistakes, direct-PR, local-only (got '$mode')" >&2
      return 1
      ;;
  esac
}
