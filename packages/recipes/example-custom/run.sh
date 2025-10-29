#!/bin/bash
# Example Custom Package Run Script
# This demonstrates how to create a run.sh script for ServoBox packages

echo "Starting example-custom package..."

# Example: Simple echo command
echo "Hello from example-custom package!"
echo "Current user: $(whoami)"
echo "Current directory: $(pwd)"
echo "Available memory: $(free -h | grep Mem | awk '{print $2}')"

# Example: Interactive command
echo ""
echo "This is an example run script. In a real package, you would:"
echo "1. Change to your package directory"
echo "2. Set up environment variables"
echo "3. Launch your application"
echo ""
echo "Example commands you might use:"
echo "  cd /home/servobox-usr/my-package"
echo "  source setup_env.sh"
echo "  ./my-executable --config config.yaml"
echo ""
echo "Press Ctrl+C to exit this example."

# Example: Keep script running (for demonstration)
# In real packages, you might run a long-running process here
echo "Example run script completed. Exiting..."
