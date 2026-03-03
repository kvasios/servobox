#!/usr/bin/env bash
# Deoxys Control run script
# Prefers tmux (split pane: franka-interface + gripper-interface). If tmux is not
# available (e.g. minimal Jetson image), runs both in the background until Enter.

set -euo pipefail

SESSION_NAME="deoxys-control"
DEOXYS_DIR="${HOME}/deoxys_control/deoxys"
CONFIG="${DEOXYS_DIR}/config/servobox.yml"
CONTROL_CONFIG="${DEOXYS_DIR}/config/control_config.yml"

if [[ ! -d "${DEOXYS_DIR}" ]] || [[ ! -f "${DEOXYS_DIR}/build/franka-interface" ]]; then
  echo "Error: deoxys_control not built. Run: servobox pkg-install deoxys-control" >&2
  exit 1
fi

if command -v tmux &>/dev/null; then
  # Use tmux: attach to existing session or create one
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Tmux session '$SESSION_NAME' already exists. Attaching..."
    exec tmux attach-session -t "$SESSION_NAME"
  fi

  tmux new-session -d -s "$SESSION_NAME" -n "deoxys"
  tmux send-keys -t "$SESSION_NAME:0.0" "cd ${DEOXYS_DIR}" C-m
  tmux send-keys -t "$SESSION_NAME:0.0" "./build/franka-interface ${CONFIG} ${CONTROL_CONFIG}" C-m
  tmux split-window -h -t "$SESSION_NAME:0"
  tmux send-keys -t "$SESSION_NAME:0.1" "cd ${DEOXYS_DIR}" C-m
  tmux send-keys -t "$SESSION_NAME:0.1" "./build/gripper-interface ${CONFIG}" C-m
  exec tmux attach-session -t "$SESSION_NAME"
fi

# No tmux: run both interfaces in background, wait for Enter then stop
echo "tmux not found; running franka-interface and gripper-interface in background."
echo "Press Enter to stop both and exit."
LOG_DIR="${HOME}/.deoxys-control-logs"
mkdir -p "${LOG_DIR}"

nohup "${DEOXYS_DIR}/build/franka-interface" "${CONFIG}" "${CONTROL_CONFIG}" &>"${LOG_DIR}/franka-interface.log" &
FPID=$!
nohup "${DEOXYS_DIR}/build/gripper-interface" "${CONFIG}" &>"${LOG_DIR}/gripper-interface.log" &
GPID=$!

cleanup() {
  kill "$FPID" "$GPID" 2>/dev/null || true
  wait "$FPID" "$GPID" 2>/dev/null || true
  exit 0
}
trap cleanup EXIT INT TERM

read -r
cleanup
