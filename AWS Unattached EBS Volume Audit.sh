#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# AWS Unattached EBS Volume Audit Script (Strictly Read-Only)
# -----------------------------------------------------------------------------
REPORT_FILE="${REPORT_FILE:-unattached_ebs_report_$(date -u '+%Y%m%d_%H%M%S').txt}"
CSV_FILE="${CSV_FILE:-}"
AWS_PROFILE_OPT="${AWS_PROFILE:-}"
REGIONS_OVERRIDE="${REGIONS_OVERRIDE:-}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  -o <path>      Output text review report path (default: ./unattached_ebs_report_<timestamp>.txt)
  -c <path>      Optional CSV export path for spreadsheet/FinOps review
  -p <profile>   AWS CLI named profile to use (default: active environment/default profile)
  -r <regions>   Comma- or space-separated list of regions (default: all enabled regions)
  -h             Show this help message

Environment overrides:
  REPORT_FILE, CSV_FILE, AWS_PROFILE, REGIONS_OVERRIDE

Notes:
  - Strictly read-only: only calls sts:GetCallerIdentity, ec2:DescribeRegions, and ec2:DescribeVolumes.
  - Monthly cost estimates use standard AWS us-east-1 baseline per-GiB-month rates:
      gp3: \$0.08/GiB | gp2: \$0.10/GiB | io1/io2: \$0.125/GiB | st1: \$0.045/GiB | sc1: \$0.015/GiB | standard: \$0.05/GiB

Examples:
  $0 -o /tmp/ebs_audit.txt
  $0 -p prod-audit -r "ap-south-1 us-east-1" -o ebs_review.txt -c ebs_review.csv
EOF
    exit 1
}

while getopts ":o:c:p:r:h" opt; do
    case "$opt" in
        o) REPORT_FILE="$OPTARG" ;;
        c) CSV_FILE="$OPTARG" ;;
        p) AWS_PROFILE_OPT="$OPTARG" ;;
        r) REGIONS_OVERRIDE="$OPTARG" ;;
        h) usage ;;
        :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
        \?) echo "Error: Invalid option -$OPTARG" >&2; usage ;;
    esac
done

for cmd in aws jq awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' is not installed or not in PATH." >&2
        exit 2
    fi
done

aws_base_args=(--output json)
if [[ -n "$AWS_PROFILE_OPT" ]]; then
    aws_base_args+=(--profile "$AWS_PROFILE_OPT")
fi

# Verify AWS credentials
if ! caller_arn="$(aws "${aws_base_args[@]}" sts get-caller-identity --query 'Arn' --output text 2>/dev/null)"; then
    echo "Error: Unable to authenticate with AWS CLI. Check credentials or -p <profile>." >&2
    exit 2
fi

# Resolve target regions
regions=()
if [[ -n "$REGIONS_OVERRIDE" ]]; then
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

mkdir -p "$(dirname "$REPORT_FILE")"
if [[ -n "$CSV_FILE" ]]; then
    mkdir -p "$(dirname "$CSV_FILE")"
fi

tmp_tsv="$(mktemp)"
trap 'rm -f "$tmp_tsv"' EXIT

echo "[INFO] Authenticated as: ${caller_arn}" >&2
echo "[INFO] Scanning ${#regions[@]} AWS region(s) for unattached (status=available) EBS volumes..." >&2

failed_regions=0

for region in "${regions[@]}"; do
    err_file="$(mktemp)"
    vol_json=""
    if ! vol_json="$(
        aws "${aws_base_args[@]}" ec2 describe-volumes \
            --region "$region" \
            --filters "Name=status,Values=available" \
            2>"$err_file"
    )"; then
        err_msg="$(tr '\n' ' ' < "$err_file" \vert{} sed 's/[[:space:]]*$//')"
        rm -f "$err_file"
        failed_regions=$(( failed_regions + 1 ))
        printf '[WARN] Skipping region %-16s (%s)\n' "$region" "${err_msg:-describe-volumes failed}" >&2
        continue
    fi
    rm -f "$err_file"

    # Extract tab-delimited fields:
    # region | volume_id | size_gib | volume_type | create_time | az | name_tag
    printf '%s' "$vol_json" | jq -r --arg reg "$region" '
        .Volumes[] |
        [
            $reg,
            (.VolumeId // "N/A"),
            (.Size // 0 | tostring),
            (.VolumeType // "unknown"),
            (.CreateTime // "N/A"),
            (.AvailabilityZone // "N/A"),
            ((.Tags // [] | map(select(.Key == "Name")) | .[0].Value) // "-")
        ] | @tsv
    ' >> "$tmp_tsv"
done

scan_time="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Calculate per-volume and aggregate monthly provisioned storage costs via awk
awk -F'\t' \
    -v scan_time="$scan_time" \
    -v caller_arn="$caller_arn" \
    -v region_count="${#regions[@]}" \
    -v failed_regions="$failed_regions" \
    -v csv_out="$CSV_FILE" '
function rate_per_gib(vtype) {
    # Standard AWS baseline provisioned storage USD/GiB-month rates
    if (vtype == "gp3")      return 0.08
    if (vtype == "gp2")      return 0.10
    if (vtype == "io1")      return 0.125
    if (vtype == "io2")      return 0.125
    if (vtype == "st1")      return 0.045
    if (vtype == "sc1")      return 0.015
    if (vtype == "
