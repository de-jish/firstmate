#!/usr/bin/env bash
# Shared closed-set validation for per-task ship delivery modes.
# bin/fm-spawn.sh owns the requirement that every ship task carries a concrete
# mode; this library lets brief creation, promotion, and live mode changes use
# that exact accepted set without restating it.
#
# `adaptive` is the proportional-validation mode: it carries a validation TIER
# (bin/fm-tier-lib.sh owns the tier set and each tier's check plan) instead of
# running one uniform pipeline for every change. It is a distinct mode rather
# than a flag on the others because its definition of done is tier-shaped.
# The three original modes are unchanged and remain valid.

fm_delivery_mode_validate() {  # <mode> [context-suffix]
  local mode=${1:-} context=${2:-}
  case "$mode" in
    no-mistakes|direct-PR|local-only|adaptive) return 0 ;;
    no-mistakes-prod-only)
      echo "error: no-mistakes-prod-only is a registry policy, not a task mode; classify this task's surface and resolve it to no-mistakes or direct-PR${context:+ $context}" >&2
      return 1
      ;;
    *)
      echo "error: --mode must be one of no-mistakes, direct-PR, local-only, adaptive (got '$mode')" >&2
      return 1
      ;;
  esac
}
