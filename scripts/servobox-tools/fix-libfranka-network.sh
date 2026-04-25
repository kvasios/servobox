#!/bin/bash
# ServoBox - Fix libfranka UDP communication issues
# Run this inside the VM if you get "UDP receive: Timeout" errors

set -e

echo "=== ServoBox libfranka Network Fix ==="
echo "This script configures the VM for libfranka UDP communication"
echo ""

# 1. Disable firewall
echo "[1/5] Disabling firewall..."
sudo ufw --force disable 2>/dev/null || true

# 2. Flush all iptables rules
echo "[2/5] Flushing iptables rules..."
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -t mangle -F
sudo iptables -t mangle -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# 3. Disable reverse path filtering (common issue with macvtap)
echo "[3/5] Disabling reverse path filtering..."
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.default.rp_filter=0
sudo sysctl -w net.ipv4.conf.enp2s0.rp_filter=0 2>/dev/null || true

# 4. Make rp_filter settings persistent
echo "[4/5] Making settings persistent..."
if ! grep -q "net.ipv4.conf.all.rp_filter" /etc/sysctl.conf 2>/dev/null; then
  echo "net.ipv4.conf.all.rp_filter=0" | sudo tee -a /etc/sysctl.conf >/dev/null
  echo "net.ipv4.conf.default.rp_filter=0" | sudo tee -a /etc/sysctl.conf >/dev/null
fi

# 5. Verify settings
echo "[5/5] Verifying configuration..."
echo ""
echo "Firewall status:"
sudo ufw status

echo ""
echo "Reverse path filtering:"
sysctl net.ipv4.conf.all.rp_filter
sysctl net.ipv4.conf.enp2s0.rp_filter 2>/dev/null || echo "  (enp2s0 interface not found - will be configured on network-setup)"

echo ""
echo "IPTables rules:"
sudo iptables -L -n | head -10

echo ""
echo "✓ Network configuration complete!"
echo ""
echo "Try running your libfranka application again:"
echo "  ./echo_robot_state 172.16.0.2"
echo ""
echo "If issues persist, run with tcpdump to monitor UDP traffic:"
echo "  sudo tcpdump -i enp2s0 udp port 1337 or udp port 1338 -v"

