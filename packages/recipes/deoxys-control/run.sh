#!/bin/bash
# Deoxys Control run script
# Starts a tmux session with franka-interface and gripper-interface

SESSION_NAME="deoxys-control"

# Check if the session already exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Tmux session '$SESSION_NAME' already exists. Attaching..."
    tmux attach-session -t "$SESSION_NAME"
    exit 0
fi

# Create a new tmux session with the franka-interface in the first pane
tmux new-session -d -s "$SESSION_NAME" -n "deoxys"

# Run franka-interface in the first (left) pane
tmux send-keys -t "$SESSION_NAME:0.0" "cd ~/deoxys_control/deoxys/" C-m
tmux send-keys -t "$SESSION_NAME:0.0" "./build/franka-interface ./config/servobox.yml" C-m

# Split the window vertically (left/right)
tmux split-window -h -t "$SESSION_NAME:0"

# Run gripper-interface in the second (right) pane
tmux send-keys -t "$SESSION_NAME:0.1" "cd ~/deoxys_control/deoxys/" C-m
tmux send-keys -t "$SESSION_NAME:0.1" "./build/gripper-interface ./config/servobox.yml" C-m

# Attach to the session
tmux attach-session -t "$SESSION_NAME"

