#!/usr/bin/env bash
# ==============================================================================
# linux-net-diag.sh - Lightweight Linux System & Network Triage Utility
# Author: Independent Linux & Network Support Specialist
# Description: Rapidly gathers OS, resource, interface, gateway, DNS, and port
#              diagnostics for remote troubleshooting without external dependencies.
# ==============================================================================

set -u

# Color codes for readable terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

header() {
    echo -e "\n${CYAN}================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

ok()   { echo -e "[${GREEN}OK${NC}]   $1"; }
warn() { echo -e "[${YELLOW}WARN${NC}] $1"; }
fail() { echo -e "[${RED}FAIL${NC}] $1"; }

echo -e "${GREEN}Starting Linux & Network Diagnostics ($(date '+%Y-%m-%d %H:%M:%S %Z'))...${NC}"

# 1. SYSTEM & RESOURCE HEALTH
header "1. SYSTEM & RESOURCE SNAPSHOT"
echo "Hostname   : $(hostname)"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "OS / Distro: ${PRETTY_NAME:-Unknown}"
fi
echo "Kernel     : $(uname -r)"
echo "Uptime     : $(uptime -p 2>/dev/null || uptime)"

echo -e "\n--- Memory & Swap Usage ---"
free -h

echo -e "\n--- Disk Partition Usage (Root & Mounts) ---"
df -h -x tmpfs -x devtmpfs | awk 'NR==1 || $5+0 >= 0 {print}'

# Flag high disk usage (>85%)
HIGH_DISK=$(df -h -x tmpfs -x devtmpfs | awk 'NR>1 && int($5) >= 85 {print $6 " (" $5 ")"}')
if [ -n "$HIGH_DISK" ]; then
    warn "High disk usage detected on: $HIGH_DISK"
else
    ok "All mounted disks are below 85% capacity."
fi

# 2. NETWORK INTERFACES & DEFAULT GATEWAY
header "2. NETWORK INTERFACES & ROUTING"
echo "--- Active IPv4 Addresses ---"
ip -4 -br addr show

DEFAULT_GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
DEFAULT_DEV=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')

if [ -n "$DEFAULT_GW" ]; then
    ok "Default Gateway: $DEFAULT_GW via interface $DEFAULT_DEV"
else
    fail "No default gateway configured! Check DHCP or static route."
fi

# 3. CONNECTIVITY & DNS RESOLUTION TESTS
header "3. GATEWAY, WAN & DNS DIAGNOSTICS"
if [ -n "$DEFAULT_GW" ]; then
    if ping -c 2 -W 2 "$DEFAULT_GW" >/dev/null 2>&1; then
        ok "Local Gateway ($DEFAULT_GW) is reachable."
    else
        fail "Cannot ping Local Gateway ($DEFAULT_GW). Check LAN cable/Wi-Fi or router firewall."
    fi
fi

if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    ok "External WAN IP (1.1.1.1) is reachable (Internet routing works)."
else
    fail "Cannot reach 1.1.1.1. Upstream ISP or router NAT issue."
fi

echo -e "\n--- Configured DNS Resolvers (/etc/resolv.conf) ---"
grep -E '^nameserver' /etc/resolv.conf 2>/dev/null || warn "No nameservers found in /etc/resolv.conf"

if getent hosts github.com >/dev/null 2>&1; then
    ok "DNS resolution works (github.com resolved successfully)."
else
    fail "DNS resolution failed! WAN may work, but domain names are not resolving."
fi

# 4. LISTENING PORTS & FIREWALL STATUS
header "4. LISTENING SERVICES & FIREWALL"
echo "--- Listening TCP/UDP Ports (ss -tulnp) ---"
ss -tuln | head -n 20

if command -v ufw >/dev/null 2>&1; then
    echo -e "\n--- UFW Firewall Status ---"
    ufw status 2>/dev/null || echo "Run with sudo to view full UFW rules."
fi

# 5. RECENT SYSTEM ERRORS & FAILED SERVICES
header "5. SYSTEMD & RECENT JOURNAL ERRORS"
if command -v systemctl >/dev/null 2>&1; then
    FAILED_UNITS=$(systemctl --failed --no-legend 2>/dev/null)
    if [ -z "$FAILED_UNITS" ]; then
        ok "Zero failed systemd units."
    else
        fail "Failed systemd services detected:"
        echo "$FAILED_UNITS"
    fi
fi

if command -v journalctl >/dev/null 2>&1; then
    echo -e "\n--- Last 5 Critical/Error Log Entries ---"
    journalctl -p 3 -n 5 --no-pager 2>/dev/null || echo "No recent priority-3 errors or insufficient permissions."
fi

echo -e "\n${GREEN}Diagnostics complete.${NC}"
