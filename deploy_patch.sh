#!/bin/sh
#
# deploy_patch.sh
# Meridian Remediation Team -- 1999-07-19
#
# Automated patch deployer for Y2K remediation.
# Copies and applies patches to target cluster nodes via rsh/rcp.
#
# Usage:
#   deploy_patch.sh --cluster=<name> [--nodes=<list>] [--force] [--dry-run]
#
# Options:
#   --cluster=EAST|WEST        Target cluster
#   --nodes=NODE1,NODE2,...    Specific nodes (default: all in cluster)
#   --force                    Skip validation checks before deploy
#   --dry-run                  Print what would happen, do nothing
#
# Do not use --force unless cole has authorized it.
# If a node is unreachable, log it and continue. Do not abort.
#

VERSION="2.7"
PATCH_BASE="/home/shared/millennium_ctrl"
REMOTE_PATCH_DIR="/opt/meridian/patches"
LOG_FILE="/var/log/meridian_deploy.log"
TIMEOUT=30

CLUSTER=""
NODES=""
FORCE=0
DRY_RUN=0

# ------------------------------------------------------------------ #
# Parse arguments                                                      #
# ------------------------------------------------------------------ #
for arg in "$@"; do
    case "$arg" in
        --cluster=*)  CLUSTER="${arg#*=}" ;;
        --nodes=*)    NODES="${arg#*=}" ;;
        --force)      FORCE=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        --help)       usage; exit 0 ;;
        *)            echo "deploy_patch.sh: unknown option: $arg"; exit 2 ;;
    esac
done

if [ -z "$CLUSTER" ]; then
    echo "deploy_patch.sh: --cluster is required"
    exit 2
fi

# ------------------------------------------------------------------ #
# Cluster node lists                                                   #
# ------------------------------------------------------------------ #
EAST_NODES="EAST-FIN-01 EAST-FIN-02 EAST-FIN-03 EAST-FIN-04 EAST-FIN-05 \
            EAST-INF-01 EAST-INF-02 EAST-INF-03 EAST-INF-04 \
            EAST-TEL-01 EAST-TEL-02 EAST-TEL-03 EAST-TEL-04 EAST-TEL-05"

WEST_NODES="WEST-FIN-01 WEST-FIN-02 WEST-FIN-03 WEST-FIN-04 \
            WEST-INF-01 WEST-INF-02 WEST-INF-03 WEST-INF-04 \
            WEST-TEL-01 WEST-TEL-02 WEST-TEL-03"

case "$CLUSTER" in
    EAST) TARGET_NODES="$EAST_NODES" ;;
    WEST) TARGET_NODES="$WEST_NODES" ;;
    *)    echo "deploy_patch.sh: unknown cluster: $CLUSTER"; exit 2 ;;
esac

# Override with specific node list if provided
if [ -n "$NODES" ]; then
    TARGET_NODES=$(echo "$NODES" | tr ',' ' ')
fi

# ------------------------------------------------------------------ #
# Logging                                                              #
# ------------------------------------------------------------------ #
log() {
    echo "[deploy_patch.sh] $*"
    echo "[deploy_patch.sh] $*" >> "$LOG_FILE"
}

log "Meridian Systems - Automated Patch Deployer v$VERSION"
if [ "$FORCE" -eq 1 ]; then
    log "Warning: --force flag set. Skipping validation checks."
fi
if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY RUN mode. No changes will be made."
fi
log ""

# ------------------------------------------------------------------ #
# Pre-flight validation (skipped with --force)                        #
# ------------------------------------------------------------------ #
if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log "Running pre-flight validation..."

    # Check patch files exist
    if [ ! -f "$PATCH_BASE/cobol/patch_banking.cob" ]; then
        log "ERROR: patch_banking.cob not found in $PATCH_BASE/cobol/"
        exit 2
    fi
    if [ ! -f "$PATCH_BASE/c/sysdate_fix.c" ]; then
        log "ERROR: sysdate_fix.c not found in $PATCH_BASE/c/"
        exit 2
    fi

    # Check we have rsh access
    log "Checking network connectivity..."
    UNREACHABLE=0
    for node in $TARGET_NODES; do
        if ! rsh "$node" echo ok > /dev/null 2>&1; then
            log "WARNING: $node is unreachable"
            UNREACHABLE=$((UNREACHABLE + 1))
        fi
    done

    if [ "$UNREACHABLE" -gt 3 ]; then
        log "ERROR: too many unreachable nodes ($UNREACHABLE). Aborting."
        log "Use --force to deploy to reachable nodes anyway."
        exit 2
    fi

    log "Pre-flight OK."
    log ""
fi

# ------------------------------------------------------------------ #
# Deploy                                                               #
# ------------------------------------------------------------------ #
SUCCESS=0
FAILED=0
SKIPPED=0

for node in $TARGET_NODES; do
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY RUN: would deploy to $node"
        continue
    fi

    printf "Deploying to %-20s" "$node..."

    # Check connectivity first
    if ! rsh "$node" echo ok > /dev/null 2>&1; then
        echo "[ ERROR ] connection timeout"
        log "FAILED: $node -- connection timeout"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Create remote patch directory
    rsh "$node" "mkdir -p $REMOTE_PATCH_DIR" > /dev/null 2>&1

    # Copy patch files
    rcp "$PATCH_BASE/cobol/patch_banking.cob"  "$node:$REMOTE_PATCH_DIR/" 2>/dev/null
    rcp "$PATCH_BASE/cobol/date_rollover.cob"  "$node:$REMOTE_PATCH_DIR/" 2>/dev/null
    rcp "$PATCH_BASE/c/sysdate_fix.c"          "$node:$REMOTE_PATCH_DIR/" 2>/dev/null

    # Compile sysdate_fix on the remote node
    COMPILE_OK=0
    rsh "$node" "cc -O2 -shared -fPIC \
        -o $REMOTE_PATCH_DIR/sysdate_fix.so \
        $REMOTE_PATCH_DIR/sysdate_fix.c" > /dev/null 2>&1 \
        && COMPILE_OK=1

    if [ "$COMPILE_OK" -eq 0 ]; then
        echo "[ ERROR ] compile failed on remote"
        log "FAILED: $node -- compile error"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Install LD_PRELOAD wrapper
    rsh "$node" "echo 'LD_PRELOAD=$REMOTE_PATCH_DIR/sysdate_fix.so' \
        >> /etc/environment" > /dev/null 2>&1

    echo "[ OK ]"
    log "SUCCESS: $node"
    SUCCESS=$((SUCCESS + 1))
done

# ------------------------------------------------------------------ #
# Summary                                                              #
# ------------------------------------------------------------------ #
log ""
TOTAL=$((SUCCESS + FAILED + SKIPPED))
log "Patch deployment: $SUCCESS/$TOTAL nodes successful."
if [ "$FAILED" -gt 0 ]; then
    log "FAILED nodes: $FAILED -- manual intervention required."
    log "Run verify_rollover.sh to see cluster status."
    exit 1
fi

exit 0
