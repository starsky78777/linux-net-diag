#!/usr/bin/env bash
# ==============================================================================
# linux-net-diag.sh - Zero-Dependency Linux & Network Triage Utility (v2)
# Reads /proc, /sys, and /etc directly; uses external tools only if present.
# ==============================================================================

set -u

# --- 1. Terminal Emulator & TTY Detection -------------------------------------
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'
    CYAN=$'\033[0;36m'
    NC=$'\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    CYAN=''
    NC=''
fi

detect_terminal() {
    local ppid pcomm
    ppid=$(awk '/^PPid:/ {print $2}' /proc/$$/status 2>/dev/null)
    pcomm=$(cat "/proc/${ppid:-0}/comm" 2>/dev/null || echo "unknown")

    printf "TTY Output   : %s\n" "$([ -t 1 ] && echo 'interactive (TTY)' || echo 'non-TTY / redirected')"
    printf "TERM / Color : %s / %s\n" "${TERM:-unset}" "${COLORTERM:-none}"
    printf "Term Program : %s\n" "${TERM_PROGRAM:-${WT_SESSION:+Windows Terminal}}"
    printf "Parent Proc  : %s (PID %s)\n" "$pcomm" "${ppid:-?}"

    if [ -n "${TMUX:-}" ]; then
        printf "Multiplexer  : tmux (%s)\n" "${TMUX%%,*}"
    elif [ -n "${STY:-}" ]; then
        printf "Multiplexer  : GNU screen (%s)\n" "$STY"
    fi
}

header() {
    printf "\n%s================================================================%s\n" "$CYAN" "$NC"
    printf "%s  %s%s\n" "$CYAN" "$1" "$NC"
    printf "%s================================================================%s\n" "$CYAN" "$NC"
}

ok()   { printf "[%sOK%s]   %s\n" "$GREEN" "$NC" "$1"; }
warn() { printf "[%sWARN%s] %s\n" "$YELLOW" "$NC" "$1"; }
fail() { printf "[%sFAIL%s] %s\n" "$RED" "$NC" "$1"; }

# Pure-Bash hex IPv4 converter for /proc/net/{route,tcp}
hex_to_ipv4() {
    local hex="$1"
    printf "%d.%d.%d.%d" \
        "$((16#${hex:6:2}))" \
        "$((16#${hex:4:2}))" \
        "$((16#${hex:2:2}))" \
        "$((16#${hex:0:2}))"
}

# --- 2. Environment, Terminal & System Snapshot (/proc & /etc) ----------------
header "1. ENVIRONMENT, TERMINAL & SYSTEM SNAPSHOT"
detect_terminal

if [ -r /proc/sys/kernel/hostname ]; then
    printf "Hostname     : %s\n" "$(cat /proc/sys/kernel/hostname 2>/dev/null)"
else
    printf "Hostname     : unknown\n"
fi

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf "OS / Distro  : %s\n" "${PRETTY_NAME:-Unknown}"
fi

if [ -r /proc/version ]; then
    printf "Kernel       : %s\n" "$(cut -d' ' -f1-3 /proc/version 2>/dev/null)"
fi

if [ -r /proc/uptime ]; then
    IFS=' ' read -r uptime_raw _ < /proc/uptime
    up_sec=${uptime_raw%%.*}
    printf "Uptime       : %dd %dh %dm\n" \
        "$((up_sec / 86400))" \
        "$(((up_sec % 86400) / 3600))" \
        "$(((up_sec % 3600) / 60))"
fi

if [ -r /proc/loadavg ]; then
    printf "Load Average : %s\n" "$(cat /proc/loadavg 2>/dev/null)"
fi

if [ -r /proc/meminfo ]; then
    awk '
        /MemTotal:/     { total = $2 }
        /MemAvailable:/ { avail = $2 }
        /SwapTotal:/    { stot  = $2 }
        /SwapFree:/     { sfree = $2 }
        END {
            if (total > 0)
                printf "Memory       : %d MiB avail / %d MiB total (%.1f%% used)\n",
                    avail / 1024, total / 1024, (1 - avail / total) * 100
            if (stot > 0)
                printf "Swap         : %d MiB free / %d MiB total\n",
                    sfree / 1024, stot / 1024
        }
    ' /proc/meminfo
fi

# --- 3. Network Interfaces & Routing (/sys & /proc/net) -----------------------
header "2. NETWORK INTERFACES & ROUTING"
found_iface=0
for iface_path in /sys/class/net/*; do
    [ -e "$iface_path" ] || continue
    found_iface=1
    iface="${iface_path##*/}"
    operstate=$(cat "$iface_path/operstate" 2>/dev/null || echo "unknown")
    rx_bytes=$(cat "$iface_path/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx_bytes=$(cat "$iface_path/statistics/tx_bytes" 2>/dev/null || echo 0)
    printf "  %-14s state=%-8s RX=%sB TX=%sB\n" "$iface" "$operstate" "$rx_bytes" "$tx_bytes"
done
[ "$found_iface" -eq 0 ] && warn "No network interfaces found in /sys/class/net"

DEFAULT_GW=""
DEFAULT_DEV=""
if [ -r /proc/net/route ]; then
    while read -r iface dest gw _flags _refcnt _use _metric _mask _rest; do
        [ "$dest" = "00000000" ] || continue
        DEFAULT_DEV="$iface"
        DEFAULT_GW=$(hex_to_ipv4 "$gw")
        break
    done < <(tail -n +2 /proc/net/route)
fi

if [ -n "$DEFAULT_GW" ] && [ "$DEFAULT_GW" != "0.0.0.0" ]; then
    ok "Default Gateway: $DEFAULT_GW via $DEFAULT_DEV"
else
    fail "No IPv4 default gateway found in /proc/net/route"
fi

# --- 4. Connectivity & DNS ----------------------------------------------------
header "3. CONNECTIVITY & DNS"
if command -v ping >/dev/null 2>&1; then
    if [ -n "$DEFAULT_GW" ] && [ "$DEFAULT_GW" != "0.0.0.0" ]; then
        if ping -c 1 -W 2 "$DEFAULT_GW" >/dev/null 2>&1; then
            ok "Gateway reachable ($DEFAULT_GW)"
        else
            fail "Gateway unreachable ($DEFAULT_GW)"
        fi
    fi

    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        ok "WAN IP reachable (1.1.1.1)"
    else
        fail "WAN IP unreachable (1.1.1.1)"
    fi
else
    warn "ping binary not installed; skipped active ICMP probes"
fi

if [ -r /etc/resolv.conf ]; then
    nameservers=$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf)
    if [ -n "$nameservers" ]; then
        printf "Nameservers  : %s\n" "$nameservers"
    else
        warn "No nameserver lines found in /etc/resolv.conf"
    fi
else
    warn "/etc/resolv.conf unreadable"
fi

# --- 5. Listening TCP Ports (/proc/net/tcp) -----------------------------------
header "4. LISTENING TCP PORTS (/proc/net/tcp)"
if [ -r /proc/net/tcp ]; then
    listen_count=0
    while read -r _ local_addr _ state _rest; do
        [ "$state" = "0A" ] || continue
        ip_hex="${local_addr%:*}"
        port_hex="${local_addr#*:}"
        printf "  Listen %s:%d\n" "$(hex_to_ipv4 "$ip_hex")" "$((16#$port_hex))"
        listen_count=$((listen_count + 1))
    done < <(tail -n +2 /proc/net/tcp)
    [ "$listen_count" -eq 0 ] && warn "No IPv4 TCP listening sockets found"
else
    warn "/proc/net/tcp unreadable"
fi

# --- 6. Init System & Log Fallbacks -------------------------------------------
header "5. INIT SYSTEM & LOGS"
INIT_NAME=$(cat /proc/1/comm 2>/dev/null || echo "unknown")
printf "PID 1 Init   : %s\n" "$INIT_NAME"

case "$INIT_NAME" in
    systemd)
        if command -v systemctl >/dev/null 2>&1; then
            failed=$(systemctl --failed --no-legend 2>/dev/null)
            if [ -z "$failed" ]; then
                ok "No failed systemd units"
            else
                fail "Failed systemd units:"
                printf "%s\n" "$failed"
            fi
        else
            warn "PID 1 is systemd but systemctl is not installed"
        fi
        ;;
    openrc-init)
        if command -v rc-status >/dev/null 2>&1; then
            rc-status --crashed 2>/dev/null || true
        else
            warn "PID 1 is openrc-init but rc-status is not installed"
        fi
        ;;
    runit)
        ls -ld /run/runit/service/* /service/* 2>/dev/null || warn "No runit service directories found"
        ;;
    *)
        warn "Non-systemd init ($INIT_NAME); inspect /etc/init.d or container supervisor manually"
        ;;
esac

if command -v journalctl >/dev/null 2>&1 && journalctl -n 1 >/dev/null 2>&1; then
    printf -- "--- Last 5 Journal Priority-3 Errors ---\n"
    journalctl -p 3 -n 5 --no-pager 2>/dev/null || warn "journalctl restricted"
elif [ -r /var/log/syslog ]; then
    printf -- "--- Last 5 /var/log/syslog Lines ---\n"
    tail -n 5 /var/log/syslog
elif [ -r /var/log/messages ]; then
    printf -- "--- Last 5 /var/log/messages Lines ---\n"
    tail -n 5 /var/log/messages
elif [ -r /dev/kmsg ]; then
    warn "No text syslog found; /dev/kmsg exists (kernel ring buffer)"
else
    warn "No standard log backend readable (run with sudo or check journald/syslog)"
fi

printf "\n%sDiagnostics complete.%s\n" "$GREEN" "$NC"
