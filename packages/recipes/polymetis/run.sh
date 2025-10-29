#!/bin/bash
# Polymetis recipe run script
# This script handles its own environment setup

# Use micromamba run to execute in the polymetis environment
micromamba run -n polymetis bash -c "
cd ~/fairo/polymetis/polymetis/python/scripts/
python launch_robot.py robot_client=franka_hardware
"