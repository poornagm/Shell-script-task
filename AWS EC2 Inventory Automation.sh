#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# AWS EC2 Multi-Region Inventory Automation Script
# -----------------------------------------------------------------------------
OUTPUT_CSV="${OUTPUT_CSV:-ec2_inventory_$(date -u '+%Y%m%d_%H%M%S').csv}"
AWS_PROFILE_OPT="${AWS_PROFILE:-}"
REGIONS_OVERRIDE="${REGIONS_OVERRIDE:-}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  -o <path>      Output CSV file path (default: ./ec2_inventory_<timestamp>.csv)
  -p <profile>   AWS CLI named profile to use (default: active environment/default profile)
  -r <regions>   Comma- or space-separated list of regions (default: all enabled regions)
  -h             Show this help message

Environment overrides:
  OUTPUT_CSV, AWS_PROFILE, REGIONS_OVERRIDE

Examples:
  $0 -o /tmp/ec2_fleet.csv
  $0 -p prod-readonly -r "ap-south-1 us-east-1" -o prod_ec2_inventory.csv
EOF
    exit 1
}

while getopts ":o:p:r:h" opt; do
    case "$opt" in
        o) OUTPUT_CSV="$OPTARG" ;;
        p) AWS_PROFILE_OPT="$OPTARG" ;;
        r) REGIONS_OVERRIDE="$OPTARG" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

for cmd in aws jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required dependency '$cmd' is not installed or not in PATH." >&2
        exit 2
    fi
done

aws_base_args=(--output json)
if [[ -n "$AWS_PROFILE_OPT" ]]; then
    aws_base_args+=(--profile "$AWS_PROFILE_OPT")
fi

# Verify AWS credentials before scanning regions
if ! caller_arn="$(aws "${aws_base_args[@]}" sts get-caller-identity --query 'Arn' --output text 2>/dev/null)"; then
    echo "Error: Unable to authenticate with AWS CLI. Check credentials or -p <profile>." >&2
    exit 2
fi

# Resolve target regions: either user-supplied list or all opted-in/enabled AWS regions
regions=()
if [[ -n "$REGIONS_OVERRIDE" ]]; then
    # Normalize commas to spaces
    normalized_regions="${REGIONS_OVERRIDE//,/ }"
    read -r -a regions <<< "$normalized_regions"
else
    read -r -a regions <<< "$(
        aws "${aws_base_args[@]}" ec2 describe-regions \
            --filters "Name=opt-in-status,Values=opt-in-not-required,opted-in" \
            --query "Regions[].RegionName" \
            --output text
    )"
fi

if (( ${#regions[@]} == 0 )); then
    echo "Error: No AWS regions resolved to scan." >&2
    exit 2
fi

csv_dir="$(dirname "$OUTPUT_CSV")"
mkdir -p "$csv_dir"

tmp_csv="$(mktemp)"
trap 'rm -f "$tmp_csv"' EXIT

# Write CSV header
printf 'region,instance_id,instance_name,instance_type,state,availability_zone,tags\n' > "$tmp_csv"

echo "[INFO] Authenticated as: ${caller_arn}"
echo "[INFO] Scanning ${#regions[@]} AWS region(s)..."

total_instances=0
failed_regions=0

for region in "${regions[@]}"; do
    printf '[INFO] Querying region %-16s ... ' "$region"

    ec2_err_file="$(mktemp)"
    ec2_json=""
    if ! ec2_json="$(aws "${aws_base_args[@]}" ec2 describe-instances --region "$region" 2>"$ec2_err_file")"; then
        err_msg="$(tr '\n' ' ' < "$ec2_err_file" | sed 's/[[:space:]]*$//')"
        rm -f "$ec2_err_file"
        failed_regions=$(( failed_regions + 1 ))
        printf 'FAILED (%s)\n' "${err_msg:-describe-instances error}" >&2
        continue
    fi
    rm -f "$ec2_err_file"

    region_count="$(printf '%s' "$ec2_json" | jq '[.Reservations[].Instances[]] | length')"
    total_instances=$(( total_instances + region_count ))
    printf '%d instance(s)\n' "$region_count"

    if (( region_count > 0 )); then
        # Extract fields and format cleanly as RFC-4180 CSV via jq @csv
        printf '%s' "$ec2_json" | jq -r --arg reg "$region" '
            .Reservations[].Instances[] |
            [
                $reg,
                (.InstanceId // ""),
                ((.Tags // [] | map(select(.Key == "Name")) | .[0].Value) // ""),
                (.InstanceType // ""),
                (.State.Name // ""),
                (.Placement.AvailabilityZone // ""),
                ((.Tags // [] | sort_by(.Key) | map("\(.Key)=\(.Value)")) | join("; "))
            ] | @csv
        ' >> "$tmp_csv"
    fi
done

mv "$tmp_csv" "$OUTPUT_CSV"

echo "----------------------------------------------------------------"
echo "[COMPLETE] Exported ${total_instances} EC2 instance(s) across ${#regions[@]} region(s)."
if (( failed_regions > 0 )); then
    echo "[WARN] ${failed_regions} region(s) could not be queried (see warnings above)." >&2
fi
echo "CSV Report: ${OUTPUT_CSV}"
