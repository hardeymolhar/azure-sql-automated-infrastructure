#!/bin/bash
# =========================================================
# PHASE 4 -- Parallel in-guest configuration orchestrator
# ---------------------------------------------------------
# Single source of truth for the config-pipeline dependency graph:
#   - vm-res-ind-190.sh and vm-res-ind-190.sh start together, right after infra
#     (db-deploy.sh Phases 1-3) is done.
#   - vm-res-ind-190.sh starts the instant vm-res-ind-190.sh succeeds; it never
#     waits on vm-res-ind-190.sh.
#   - If AD fails, Windows must never start.
#   - If Linux fails, that must NOT block or skip Windows.
#   - Overall exit is non-zero if ANY pipeline failed or was skipped.
#
# Live monitoring: every pipeline line streams into this terminal tagged
# [ad] / [linux] / [windows], while tee keeps an untagged copy per pipeline in
# $LOG_DIR for post-mortem. A FAILED summary row prints the Ansible fatal lines
# plus the log tail, so the failing task is visible without opening the log.
# =========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source "./env.conf"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$PROJECT_ROOT/.logs/vm-config-$TIMESTAMP"
mkdir -p "$LOG_DIR"

AD_LOG="$LOG_DIR/vm-config-ad.log"
LINUX_LOG="$LOG_DIR/vm-config-linux.log"
WINDOWS_LOG="$LOG_DIR/vm-config-windows.log"

WINDOWS_PID=""
WINDOWS_STATUS="SKIPPED"

# Streams a pipeline's output live into this terminal, each line tagged so
# concurrent pipelines stay attributable, while tee keeps an untagged copy in
# the per-run log. awk (not sed) does the tagging because awk's fflush() gives
# line-buffered output on both GNU and BSD -- sed block-buffers when stdout is
# not a tty (e.g. this orchestrator piped through tee), which would defeat live
# monitoring. With pipefail inherited by the background subshell, the job's
# exit status is the pipeline script's own status (tee/awk always succeed).
# Launched through `bash` deliberately: a lost exec bit on a pipeline script
# must not be able to kill a deployment mid-flight.
run_pipeline() {
  local script="$1" log="$2" tag="$3"
  bash "./$script" 2>&1 | tee "$log" | awk -v tag="$tag" '{ print tag $0; fflush() }'
}

# Fail fast: a missing pipeline script must abort BEFORE anything starts, not
# surface minutes into the run (Windows' absence would otherwise only be
# discovered after AD's promotion completed).
for pipeline in vm-res-ind-190.sh vm-res-ind-190.sh vm-res-ind-190.sh; do
  if [[ ! -f "./$pipeline" ]]; then
    echo -e "${RED}Missing pipeline script: $SCRIPT_DIR/$pipeline -- aborting before any pipeline starts.${NC}"
    exit 1
  fi
done

# Best-effort: signals in-flight pipelines on Ctrl-C/SIGTERM. Not a rollback --
# an interrupted AD promotion or WSFC formation needs manual verification.
# Each PID is the run_pipeline subshell, not the ansible-playbook it spawned;
# under a non-TTY invocation (nohup, CI) that grandchild can survive the kill.
cleanup_on_interrupt() {
  echo -e "\n${RED}Interrupted -- signalling in-flight pipelines...${NC}"
  [[ -n "${AD_PID:-}" ]]    && kill "$AD_PID"    2>/dev/null || true
  [[ -n "${LINUX_PID:-}" ]] && kill "$LINUX_PID" 2>/dev/null || true
  [[ -n "$WINDOWS_PID" ]]   && kill "$WINDOWS_PID" 2>/dev/null || true
  echo -e "${RED}Partial logs: $LOG_DIR${NC}"
  exit 130
}
trap cleanup_on_interrupt INT TERM

echo -e "${BLUE}Starting vm-res-ind-190.sh and vm-res-ind-190.sh concurrently...${NC}"
echo "Logs: $LOG_DIR"

run_pipeline vm-res-ind-190.sh "$AD_LOG" "[ad]      " &
AD_PID=$!
echo "  vm-res-ind-190.sh     started (PID $AD_PID)"

run_pipeline vm-res-ind-190.sh "$LINUX_LOG" "[linux]   " &
LINUX_PID=$!
echo "  vm-res-ind-190.sh  started (PID $LINUX_PID)"

# Gate Windows on AD ONLY -- wait for AD regardless of Linux's runtime.
AD_STATUS=0
wait "$AD_PID" || AD_STATUS=$?

if [[ "$AD_STATUS" -eq 0 ]]; then
  echo -e "${GREEN}vm-config-ad.sh succeeded -- starting vm-res-ind-190.sh...${NC}"
  run_pipeline vm-res-ind-190.sh "$WINDOWS_LOG" "[windows] " &
  WINDOWS_PID=$!
  echo "  vm-res-ind-190.sh started (PID $WINDOWS_PID)"
else
  echo -e "${RED}vm-config-ad.sh FAILED (exit $AD_STATUS) -- vm-res-ind-190.sh will NOT start.${NC}"
fi

# Linux never gates anything; collect its result whenever it finishes.
LINUX_STATUS=0
wait "$LINUX_PID" || LINUX_STATUS=$?

if [[ -n "$WINDOWS_PID" ]]; then
  WINDOWS_STATUS=0
  wait "$WINDOWS_PID" || WINDOWS_STATUS=$?
fi

trap - INT TERM

print_result() {
  local name="$1" pid="${2:-N/A}" status="$3" log="$4"
  if [[ "$status" == "SKIPPED" ]]; then
    echo -e "  ${YELLOW}SKIPPED${NC}  $name (never started -- vm-res-ind-190.sh failed)"
  elif [[ "$status" -eq 0 ]]; then
    echo -e "  ${GREEN}OK${NC}       $name (PID $pid, log: $log)"
  else
    echo -e "  ${RED}FAILED${NC}   $name (PID $pid, exit $status, log: $log)"
    # Surface the failing Ansible task without making the user open the log.
    # grep may find nothing (non-ansible failure) -- '|| true' keeps set -e calm.
    local fatal=""
    fatal=$(grep -E '^(fatal|failed):' "$log" | tail -n 5) || true
    if [[ -n "$fatal" ]]; then
      echo "$fatal" | sed 's/^/           | /'
    fi
    echo "           ---- last 25 log lines ----"
    tail -n 25 "$log" | sed 's/^/           | /'
  fi
}

echo
echo "=========================================================="
echo " In-guest configuration summary"
echo "=========================================================="
print_result "vm-res-ind-190.sh     " "$AD_PID" "$AD_STATUS" "$AD_LOG"
print_result "vm-res-ind-190.sh  " "$LINUX_PID" "$LINUX_STATUS" "$LINUX_LOG"
print_result "vm-res-ind-190.sh" "$WINDOWS_PID" "$WINDOWS_STATUS" "$WINDOWS_LOG"
echo "=========================================================="

OVERALL_STATUS=0
if [[ "$AD_STATUS" -ne 0 ]]; then OVERALL_STATUS=1; fi
if [[ "$LINUX_STATUS" -ne 0 ]]; then OVERALL_STATUS=1; fi
if [[ "$WINDOWS_STATUS" != "SKIPPED" && "$WINDOWS_STATUS" -ne 0 ]] || [[ "$WINDOWS_STATUS" == "SKIPPED" ]]; then
  OVERALL_STATUS=1
fi

if [[ "$OVERALL_STATUS" -eq 0 ]]; then
  echo -e "${GREEN}All in-guest configuration pipelines completed successfully.${NC}"
else
  echo -e "${RED}One or more in-guest configuration pipelines failed -- see logs above.${NC}"
fi

exit "$OVERALL_STATUS"
