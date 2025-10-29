#!/usr/bin/env bash
set -euo pipefail

# Real-time control tools installation script
# This script installs tools useful for high-frequency real-time control systems

echo "Installing real-time control tools..."

. "$(cd "$(dirname "$0")/.." && pwd)/scripts/pkg-helpers.sh"

# Install real-time and control system tools (additional to build-image.sh defaults)
apt_update
apt_install \
    iotop \
    linux-tools-common \
    ethtool \
    tcpdump \
    can-utils \
    iproute2 \
    net-tools

# Install additional real-time development tools
# Keep runtime libs minimal; add as-needed later
apt_install \
    libnuma1 \
    libcap2 \
    libssl3 || true

# Create real-time testing script for 1kHz control loops
cat > /home/servobox-usr/rt-control-test.sh << 'EOF'
#!/bin/bash
# Real-time control loop testing script
# Tests system performance for high-frequency control applications

echo "Real-time Control System Test"
echo "============================="
echo "Testing system performance for 1kHz control loops..."
echo

# Test 1: Basic latency test
echo "1. Basic latency test (cyclictest)"
cyclictest -t1 -p 80 -i 1000 -l 10000 -q --duration=10

echo
echo "2. High-frequency stress test"
stress-ng --cpu 1 --timeout 10s --metrics-brief

echo
echo "3. Memory latency test"
stress-ng --vm 1 --vm-bytes 1G --timeout 10s --metrics-brief

echo
echo "Real-time control system test completed!"
echo "For 1kHz control loops, aim for < 100μs latency"
EOF

chmod +x /home/servobox-usr/rt-control-test.sh
chown servobox-usr:servobox-usr /home/servobox-usr/rt-control-test.sh

# Create system monitoring script for real-time control
cat > /home/servobox-usr/rt-monitor.sh << 'EOF'
#!/bin/bash
# Real-time system monitoring script
# Monitors system performance for real-time control applications

echo "Real-time System Monitor"
echo "========================"
echo "Monitoring system performance for real-time control..."
echo

# Show current CPU governor settings
echo "CPU Governor Status:"
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [[ -f "$cpu" ]]; then
        cpu_num=$(basename $(dirname $(dirname "$cpu")))
        governor=$(cat "$cpu" 2>/dev/null || echo "unknown")
        echo "  CPU $cpu_num: $governor"
    fi
done
echo

# Show real-time group membership
echo "Real-time Group Members:"
getent group realtime 2>/dev/null | cut -d: -f4 || echo "  No realtime group found"
echo

# Show current system load
echo "System Load:"
uptime
echo

# Show memory usage
echo "Memory Usage:"
free -h
echo

# Show network interfaces
echo "Network Interfaces:"
ip -brief link show
echo

echo "Real-time monitoring completed!"
echo "Use 'cyclictest' for latency testing"
EOF

chmod +x /home/servobox-usr/rt-monitor.sh
chown servobox-usr:servobox-usr /home/servobox-usr/rt-monitor.sh

echo "Real-time control tools installation completed!"
echo "Available tools:"
echo "  - /home/servobox-usr/rt-control-test.sh (system performance test)"
echo "  - /home/servobox-usr/rt-monitor.sh (system monitoring)"
echo "  - cyclictest (latency testing - from build-image.sh)"
echo "  - stress-ng (system stress testing - from build-image.sh)"
echo "  - htop (system monitoring - from build-image.sh)"
echo "  - can-utils (CAN bus tools)"
echo "  - ethtool (network interface tuning)"
echo "  - iotop (I/O monitoring)"
echo "  - perf-tools (performance analysis)"
echo "  - tcpdump (network analysis)"

apt_cleanup
