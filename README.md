# linux-net-diag.sh

A zero-dependency Bash diagnostic utility built for rapid **Linux system and home/office network troubleshooting**.

## Why I Built This
When diagnosing remote Linux desktops, servers, or router connectivity issues over SSH or screen-share, running a dozen separate commands wastes valuable time. `linux-net-diag.sh` collects the most critical system and network health signals in under 5 seconds with clear `[OK]`, `[WARN]`, and `[FAIL]` status indicators.

## What It Checks
1. **System & Resource Health:** OS release, kernel, uptime, RAM/swap utilization, and disk partition warnings (`>=85%`).
2. **Interfaces & Routing:** Active IPv4 interfaces (`ip -4 -br addr`) and default gateway detection.
3. **Connectivity & DNS Triage:** Isolates local router issues (`ping` gateway), upstream ISP/NAT issues (`ping 1.1.1.1`), and DNS failures (`getent hosts`).
4. **Ports & Firewall:** Lists active listening TCP/UDP sockets (`ss -tuln`) and checks `ufw` status.
5. **Service & Log Errors:** Flags failed `systemd` units and pulls recent high-priority `journalctl` errors.

## Usage
```bash
git clone [https://github.com/YOUR_USERNAME/linux-net-diag.git](https://github.com/YOUR_USERNAME/linux-net-diag.git)
cd linux-net-diag
chmod +x linux-net-diag.sh
./linux-net-diag.sh
