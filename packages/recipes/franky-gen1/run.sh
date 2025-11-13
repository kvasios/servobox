#!/bin/bash
# Franky Gen1 run script
# Launches an interactive Python session with franky pre-imported

echo "================================================"
echo "Starting interactive Python session with Franky (Gen1)"
echo "================================================"
echo ""
echo "Franky has been imported for you as 'franky'"
echo "libfranka version: 0.9.2"
echo ""
echo "Quick start examples:"
echo "  robot = franky.Robot('172.16.0.2')     # Connect to robot"
echo "  gripper = franky.Gripper('172.16.0.2') # Connect to gripper"
echo ""
echo "See ~/franky/examples/ for more examples"
echo "================================================"
echo ""

# Create a temporary Python startup script
TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'PYEOF'
import franky
print("libfranka version: 0.9.2")
print("Ready! Type your commands below:\n")
PYEOF

# Use micromamba run to execute in the franky-gen1 environment
PYTHONSTARTUP="$TMPFILE" micromamba run -n franky-gen1 python -i

# Clean up
rm -f "$TMPFILE"

