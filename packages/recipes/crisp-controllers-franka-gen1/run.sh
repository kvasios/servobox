#!/usr/bin/env bash
set -euo pipefail

ROBOT_IP="${1:-${ROBOT_IP:-172.16.0.2}}"

REPO_DIR="${HOME}/pixi_panda_ros2"
if [[ ! -d "${REPO_DIR}" ]]; then
  echo "Error: ${REPO_DIR} not found. Install crisp-controllers-franka-gen1 first." >&2
  exit 1
fi

PIXI="${HOME}/.pixi/bin/pixi"
if [[ ! -x "${PIXI}" ]]; then
  PIXI="$(command -v pixi || true)"
fi
if [[ -z "${PIXI}" || ! -x "${PIXI}" ]]; then
  echo "Error: pixi executable not found. Re-run install or ensure Pixi is on PATH." >&2
  exit 1
fi

cd "${REPO_DIR}"
exec "${PIXI}" run -e jazzy franka "robot_ip:=${ROBOT_IP}"

