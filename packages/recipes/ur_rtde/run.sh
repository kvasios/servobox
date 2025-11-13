#!/bin/bash
# ur_rtde run script
# Launches an interactive Python session with ur_rtde pre-imported

echo "================================================"
echo "Starting interactive Python session with ur_rtde"
echo "================================================"
echo ""
echo "ur_rtde has been imported for you"
echo ""
echo "Quick start examples:"
echo "  rtde_c = rtde_control.RTDEControlInterface('192.168.1.20')  # Connect to robot"
echo "  rtde_r = rtde_receive.RTDEReceiveInterface('192.168.1.20')  # Receive data"
echo "  pos = rtde_r.getActualTCPPose()  # Get current TCP position"
echo "  rtde_c.moveJ([0, -1.57, 1.57, -1.57, -1.57, 0], 1.05, 1.4)  # Move joints"
echo ""
echo "See ~/ur_rtde/examples/ for more examples"
echo "================================================"
echo ""

# Create a temporary Python startup script
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'PYEOF'
import rtde_control
import rtde_receive
import rtde_io
print("ur_rtde modules imported:")
print("  - rtde_control (robot control)")
print("  - rtde_receive (data reception)")
print("  - rtde_io (digital/analog I/O)")
print("\nReady! Type your commands below:\n")
PYEOF

# Use micromamba run to execute in the ur_rtde environment
PYTHONSTARTUP="$TMPFILE" micromamba run -n ur_rtde python -i

# Clean up
rm -f "$TMPFILE"

