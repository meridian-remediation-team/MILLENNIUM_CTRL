#!/bin/sh
#
# verify_rollover.sh
# Meridian Remediation Team -- 1999-08-31
#
# Rollover verification suite. Checks each node in a cluster for
# patch status and date handling correctness.
#
# Run this after deploy_patch.sh. Run it again an hour before midnight.
# Run it again ten minutes before midnight.
# Then stop running it and start praying.
#
# Usage:
#   verify_rollover.sh --cluster=<name> [--dry-run] [--node=<name>]
#
# Output:
#   Per-node status: PATCHED / WARNING / UNPATCHED
#   Summary with estimated completion time
#
# Exit codes:
#   0  -- all nodes PATCHED
#   1  -- some nodes WARNING or UNPATCHED
#   2  -- error
#

VERSION="3.1"
TIMEOUT=15
LOG_FILE="/var/log/meridian_verify.log"

CLUSTER=""
DRY_RUN=0
SINGLE_NODE=""

for arg in "$@"; do
    case "$arg" in
        --cluster=*)  CLUSTER="${arg#*=}" ;;
        --dry-run)    DRY_RUN=1 ;;
        --node=*)     SINGLE_NODE="${arg#*=}" ;;
        *)            echo "verify_rollover.sh: unknown option: $arg"; exit 2 ;;
    esac
done

if [ -z "$CLUSTER" ] && [ -z "$SINGLE_NODE" ]; then
    echo "verify_rollover.sh: --cluster or --node required"
    exit 2
fi

EAST_NODES="EAST-FIN-01 EAST-FIN-02 EAST-FIN-03 EAST-FIN-04 EAST-FIN-05 \
            EAST-INF-01 EAST-INF-02 EAST-INF-03 EAST-INF-04 \
            EAST-TEL-01 EAST-TEL-02 EAST-TEL-03 EAST-TEL-04 EAST-TEL-05"

WEST_NODES="WEST-FIN-01 WEST-FIN-02 WEST-FIN-03 WEST-FIN-04 \
            WEST-INF-01 WEST-INF-02 WEST-INF-03 WEST-INF-04 \
            WEST-TEL-01 WEST-TEL-02 WEST-TEL-03"

if [ -n "$SINGLE_NODE" ]; then
    TARGET_NODES="$SINGLE_NODE"
elif [ "$CLUSTER" = "EAST" ]; then
    TARGET_NODES="$EAST_NODES"
elif [ "$CLUSTER" = "WEST" ]; then
    TARGET_NODES="$WEST_NODES"
else
    echo "verify_rollover.sh: unknown cluster: $CLUSTER"
    exit 2
fi

log() {
    echo "[verify_rollover.sh] $*"
    echo "[verify_rollover.sh] $*" >> "$LOG_FILE"
}

log "Meridian Systems - Rollover Verification Suite v$VERSION"
if [ "$DRY_RUN" -eq 1 ]; then
    log "Target cluster: $CLUSTER (DRY RUN)"
else
    log "Target cluster: $CLUSTER"
fi
log ""

COUNT_PATCHED=0
COUNT_WARNING=0
COUNT_UNPATCHED=0
COUNT_TOTAL=0
RATE_ESTIMATE=0

check_node() {
    local node="$1"

    if [ "$DRY_RUN" -eq 1 ]; then
        printf "Checking node: %-20s [ DRY RUN ]\n" "$node ............"
        return 0
    fi

    # Check connectivity
    if ! rsh "$node" echo ok > /dev/null 2>&1; then
        printf "Checking node: %-20s [ UNREACHABLE ]\n" "$node ..........."
        COUNT_UNPATCHED=$((COUNT_UNPATCHED + 1))
        return 1
    fi

    # Check if sysdate_fix.so is installed
    local has_fix=0
    rsh "$node" "test -f /opt/meridian/patches/sysdate_fix.so" 2>/dev/null \
        && has_fix=1

    # Check if LD_PRELOAD is set
    local has_preload=0
    rsh "$node" "grep -q sysdate_fix /etc/environment" 2>/dev/null \
        && has_preload=1

    # Check for known-bad patterns in running processes
    local has_warnings=0
    local warn_detail=""
    warn_detail=$(rsh "$node" \
        "strings /usr/local/lib/fincore.so 2>/dev/null | grep -c '%02d'" 2>/dev/null)
    if [ "${warn_detail:-0}" -gt 0 ]; then
        has_warnings=1
    fi

    # Determine status
    if [ "$has_fix" -eq 1 ] && [ "$has_preload" -eq 1 ] && [ "$has_warnings" -eq 0 ]; then
        printf "Checking node: %-20s [ PATCHED  ] date logic OK\n" "$node ..........."
        COUNT_PATCHED=$((COUNT_PATCHED + 1))
    elif [ "$has_fix" -eq 1 ] && [ "$has_warnings" -eq 1 ]; then
        local detail
        detail=$(rsh "$node" \
            "grep -n 'CALC_INTEREST_YR\|log_rotate\|GENERATE_INVOICE' \
            /usr/local/lib/fincore.so 2>/dev/null | head -1")
        printf "Checking node: %-20s [ WARNING  ] partial patch -- %s\n" \
            "$node ..........." "${detail:-unresolved pattern in binary}"
        COUNT_WARNING=$((COUNT_WARNING + 1))
    else
        printf "Checking node: %-20s [ UNPATCHED ]\n" "$node ..........."
        COUNT_UNPATCHED=$((COUNT_UNPATCHED + 1))
    fi
}

for node in $TARGET_NODES; do
    check_node "$node"
    COUNT_TOTAL=$((COUNT_TOTAL + 1))
done

log ""
log "SUMMARY:"
log "  PATCHED:    $COUNT_PATCHED / $COUNT_TOTAL nodes"
log "  WARNING:    $COUNT_WARNING / $COUNT_TOTAL nodes"
log "  UNPATCHED:  $COUNT_UNPATCHED / $COUNT_TOTAL nodes"

if [ "$COUNT_UNPATCHED" -gt 0 ] || [ "$COUNT_WARNING" -gt 0 ]; then
    REMAINING=$((COUNT_UNPATCHED + COUNT_WARNING))
    MINS_PER_NODE=18
    TOTAL_MINS=$((REMAINING * MINS_PER_NODE))
    HOURS=$((TOTAL_MINS / 60))
    MINS=$((TOTAL_MINS % 60))
    log ""
    log "  CLUSTER STATUS: *** NOT READY FOR ROLLOVER ***"
    log "  Estimated patch completion at current rate: ${HOURS}h ${MINS}m"
    exit 1
fi

log ""
log "  CLUSTER STATUS: READY FOR ROLLOVER"
exit 0
