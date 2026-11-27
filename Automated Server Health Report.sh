#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Automated Server Health Report (CSV Exporter)
# -----------------------------------------------------------------------------
CSV_OUTPUT="${1:-/var/log/server_health.csv}"
MOUNT_POINT="${2:-/}"

usage() {
    cat <<EOF
Usage: $0 [csv_output_path] [mount_point]

Arguments:
  [csv_output_path]  Destination CSV file path (default: /var/log/server_health.csv)
  [mount_point]      Filesystem mount point for disk utilization (default: /)

Example:
  $0 ./server_health.csv /
EOF
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

if [[ ! -d "$MOUNT_POINT" ]]; then
    echo "Error: Mount point '$MOUNT_POINT' does not exist." >&2
    exit 2
fi

csv_dir="$(dirname "$CSV_OUTPUT")"
mkdir -p "$csv_dir"

escape_csv() {
    local val="$1"
    val="${val//\"/\"\"}"
    printf '"%s"' "$val"
}

get_ip_address() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
        if [[ -z "$ip" ]]; then
            ip="$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR==1 {split($4, a, "/"); print a[1]}')"
        fi
    fi
    if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    printf '%s' "${ip:-N/A}"
}

get_uptime_summary() {
    if command -v uptime >/dev/null 2>&1; then
        uptime -p 2>/dev/null || uptime | sed -E 's/.*up ([^,]+(,[^,]+)?),.*load average.*/\1/' | xargs
    elif [[ -r /proc/uptime ]]; then
        awk '{
            secs = int($1)
            days = int(secs / 86400)
            hrs = int((secs % 86400) / 3600)
            mins = int((secs % 3600) / 60)
            printf "%dd %dh %dm", days, hrs, mins
        }' /proc/uptime
    else
        printf 'N/A'
    fi
}

get_cpu_utilization() {
    if [[ -r /proc/stat ]]; then
        local line1 line2 idle1 total1 idle2 total2 diff_idle diff_total
        line1="$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)"
        sleep 0.5
        line2="$(awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat)"

        idle1="$(awk '{print $4 + $5}' <<< "$line1")"
        total1="$(awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}' <<< "$line1")"
        idle2="$(awk '{print $4 + $5}' <<< "$line2")"
        total2="$(awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}' <<< "$line2")"

        diff_idle=$(( idle2 - idle1 ))
        diff_total=$(( total2 - total1 ))

        if (( diff_total > 0 )); then
            awk -v di="$diff_idle" -v dt="$diff_total" 'BEGIN {printf "%.1f", ((dt - di) / dt) * 100}'
        else
            printf '0.0'
        fi
    elif command -v top >/dev/null 2>&1; then
        top -bn1 | awk '/^%Cpu\(s\):/ {idle=$8; gsub(/[^0-9.]/,"",idle); printf "%.1f", 100 - idle}'
    else
        printf 'N/A'
    fi
}

get_memory_utilization() {
    if [[ -r /proc/meminfo ]]; then
        awk '
            /^MemTotal:/ {total = $2}
            /^MemAvailable:/ {avail = $2}
            END {
                if (total > 0 && avail >= 0) {
                    used = total - avail
                    printf "%.1f", (used / total) * 100
                } else {
                    print "N/A"
                }
            }
        ' /proc/meminfo
    elif command -v free >/dev/null 2>&1; then
        free -m | awk '/^Mem:/ {if ($2 > 0) printf "%.1f", ($3 / $2) * 100; else print "N/A"}'
    else
        printf 'N/A'
    fi
}

get_disk_utilization() {
    local pct
    pct="$(df -P "$MOUNT_POINT" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
    printf '%s' "${pct:-N/A}"
}

timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
host_name="$(hostname -f 2>/dev/null || hostname)"
ip_addr="$(get_ip_address)"
uptime_val="$(get_uptime_summary)"
cpu_pct="$(get_cpu_utilization)"
mem_pct="$(get_memory_utilization)"
disk_pct="$(get_disk_utilization)"

header="timestamp,hostname,ip_address,uptime,cpu_percent,memory_percent,disk_percent"

if [[ ! -s "$CSV_OUTPUT" ]]; then
    printf '%s\n' "$header" > "$CSV_OUTPUT"
fi

row="$(
    printf '%s,%s,%s,%s,%s,%s,%s' \
        "$(escape_csv "$timestamp")" \
        "$(escape_csv "$host_name")" \
        "$(escape_csv "$ip_addr")" \
        "$(escape_csv "$uptime_val")" \
        "$(escape_csv "$cpu_pct")" \
        "$(escape_csv "$mem_pct")" \
        "$(escape_csv "$disk_pct")"
)"

printf '%s\n' "$row" >> "$CSV_OUTPUT"

echo "Recorded health snapshot to '$CSV_OUTPUT':"
echo "  Timestamp : $timestamp"
echo "  Hostname  : $host_name"
echo "  IP        : $ip_addr"
echo "  Uptime    : $uptime_val"
echo "  CPU       : ${cpu_pct}%"
echo "  Memory    : ${mem_pct}%"
echo "  Disk ($MOUNT_POINT): ${disk_pct}%"
