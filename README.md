# linux-net-diag.sh

A zero-dependency Bash diagnostic utility for rapid **Linux system and network triage**.

## Why I Built This
When diagnosing remote Linux desktops, servers, containers, or router connectivity issues, heavy userland wrappers (`ip`, `ss`, `systemctl`, `journalctl`) are not always installed or consistent across init systems. `linux-net-diag.sh` reads `/proc`, `/sys`, and `/etc` directly and uses external commands only as optional fallbacks.

## What It Checks (v2)
1. **Environment, Terminal & System Snapshot:** Detects interactive TTY vs. redirected output (disabling ANSI colors automatically when piped/saved), terminal emulator and multiplexer context (`TERM`, `COLORTERM`, `TERM_PROGRAM`, `TMUX`, `STY`, parent process), hostname, OS release, kernel, uptime, load average, and memory/swap from `/proc/meminfo`.
2. **Network Interfaces & Routing:** Lists interfaces, operational states, and RX/TX byte counters from `/sys/class/net/*`, and resolves the default IPv4 gateway from `/proc/net/route`.
3. **Connectivity & DNS:** Runs gateway and WAN (`1.1.1.1`) reachability checks when `ping` is present, and reads configured nameservers from `/etc/resolv.conf`.
4. **Listening TCP Ports:** Parses `/proc/net/tcp` (state `0A`) to list active listening sockets without `ss` or `netstat`.
5. **Init System & Log Fallbacks:** Inspects `/proc/1/comm` (`systemd`, `openrc-init`, `runit`, or custom init) and falls back across `journalctl`, `/var/log/syslog`, `/var/log/messages`, and `/dev/kmsg`.

## Usage
```bash
git clone git@github.com:starsky78777/linux-net-diag.git
cd linux-net-diag
chmod +x linux-net-diag.sh
./linux-net-diag.sh
./linux-net-diag.sh > diag-report.txt
