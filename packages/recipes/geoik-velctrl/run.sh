#!/usr/bin/env bash
# Run the geoik-velctrl velocity control server

# Change to the project directory
cd ~/geoik-velctrl || { echo "Error: geoik-velctrl not found in home directory" >&2; exit 1; }

# Default robot IP (can be overridden by environment variable or argument)
ROBOT_IP="${FRANKA_IP:-${1:-172.16.0.2}}"

echo "Starting geoik-velctrl velocity server..."
echo "Robot IP: ${ROBOT_IP}"
echo "Press Ctrl+C to stop the server"
echo ""

# Run the velocity server
./franka_velocity_server "${ROBOT_IP}" true vs