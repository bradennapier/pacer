#!/usr/bin/env bash
#
# EXAMPLE 05: Single-Flight Execution
# ====================================
#
# This example demonstrates pacer's SINGLE-FLIGHT guarantee: for any given ID,
# your command will NEVER overlap with itself - even if execution takes longer
# than the delay interval.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# What happens if your command takes 5 seconds, but events arrive every 100ms?
# Without single-flight protection, you'd have 50 concurrent executions fighting
# over the same resources - causing race conditions, file corruption, and chaos.
#
# Example scenarios that cause problems without single-flight:
#   - Database migrations running simultaneously
#   - Git operations overlapping (corrupted repos)
#   - Build processes fighting over temp files
#   - Config writers overwriting each other
#
# WHAT PACER PROVIDES:
# --------------------
# 1. Run lock per ID - held for ENTIRE command duration
# 2. Command NEVER overlaps itself for the same ID
# 3. Subsequent calls are queued (exit 77) or use --no-wait (exit 76)
# 4. Works via flock filesystem locking
#
# HOW IT WORKS:
# -------------
# 1. Before executing, pacer acquires an exclusive run lock for the ID
# 2. Lock is held until command completes (success or failure)
# 3. While lock is held, other calls for same ID cannot execute
# 4. Those calls update the pending command (last-call-wins) and exit
#
# COMPARISON WITH FLOCK:
# ----------------------
# Raw flock gives you mutual exclusion but no timing coordination:
#   flock /tmp/build.lock make    # blocks until lock available
#
# Pacer adds:
#   - Debounce/throttle timing
#   - Cross-mode coordination
#   - Last-call-wins arguments
#   - Status/reset operations
#   - Process tracking and stamps
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Single-Flight Execution ==="
echo ""
echo "Commands are guaranteed to NEVER overlap for the same ID."
echo "This prevents race conditions even with slow commands."
echo ""

# Cleanup
"$PACER" --reset-all demo-single-flight 2>/dev/null || true

echo "SCENARIO: Slow Command (2 seconds) with Rapid Events"
echo "-----------------------------------------------------"
echo "We'll trigger events every 200ms while the command runs for 2 seconds."
echo ""
echo "WITHOUT single-flight: Multiple overlapping executions (race condition!)"
echo "WITH single-flight: ONE execution at a time, subsequent calls queued"
echo ""

# Track execution overlap
LOG_FILE="/tmp/single-flight-demo.log"
rm -f "$LOG_FILE"
touch "$LOG_FILE"

# The slow command - simulates a build/migration that takes 2 seconds
slow_command() {
    local start_time
    start_time="$(date '+%H:%M:%S.%3N')"
    echo "[$start_time] >>> STARTED (will take 2 seconds, arg: $1)" | tee -a "$LOG_FILE"

    # Check for overlap
    if grep -q ">>> RUNNING" "$LOG_FILE" 2>/dev/null; then
        echo "[$start_time] !!! OVERLAP DETECTED - this should NOT happen!" | tee -a "$LOG_FILE"
    fi

    echo ">>> RUNNING" >> "$LOG_FILE"
    sleep 2
    sed -i '/>>> RUNNING/d' "$LOG_FILE" 2>/dev/null || true

    local end_time
    end_time="$(date '+%H:%M:%S.%3N')"
    echo "[$end_time] >>> FINISHED (arg: $1)" | tee -a "$LOG_FILE"
}
export -f slow_command
export LOG_FILE

echo "Starting rapid event simulation..."
echo ""

# Fire 10 events over 2 seconds while command runs
# First event starts the command, subsequent events update pending args
for i in {1..10}; do
    echo "[$(date '+%H:%M:%S.%3N')] Event $i - calling pacer..."

    # Use throttle with leading=true to get immediate first execution
    "$PACER" --throttle --leading true demo-single-flight 100 \
        bash -c "slow_command 'event_$i'" &

    pid=$!

    # Check exit code (need to wait briefly for process to start/exit)
    sleep 0.1
    if kill -0 $pid 2>/dev/null; then
        # Still running - it's either executing or runner waiting
        wait $pid 2>/dev/null || true
    fi

    sleep 0.2  # 200ms between events
done

echo ""
echo "Waiting for final execution to complete..."
wait
sleep 0.5

echo ""
echo "=== Execution Log ==="
cat "$LOG_FILE"
echo ""

# Count executions
started_count=$(grep -c ">>> STARTED" "$LOG_FILE" || echo "0")
overlap_count=$(grep -c "OVERLAP" "$LOG_FILE" || echo "0")

echo "=== Results ==="
echo "Events sent: 10"
echo "Command executions: $started_count"
echo "Overlaps detected: $overlap_count"
echo ""

if [[ "$overlap_count" == "0" ]]; then
    echo "SUCCESS: No overlapping executions!"
else
    echo "ERROR: Overlaps detected (this shouldn't happen with pacer)"
fi
echo ""

# Cleanup
rm -f "$LOG_FILE"
"$PACER" --reset-all demo-single-flight 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. SINGLE-FLIGHT: Command NEVER overlaps itself for the same ID"
echo ""
echo "2. How it works:"
echo "   - First call acquires run lock and executes"
echo "   - Subsequent calls update pending args and exit (code 77)"
echo "   - After current execution, runner checks for pending work"
echo "   - Last-call-wins: only the latest arguments are used"
echo ""
echo "3. Exit codes indicate what happened:"
echo "   - 0:  Command executed (returns command's exit code)"
echo "   - 77: Queued - runner will use your args"
echo "   - 76: Skipped (--no-wait mode, runner was busy)"
echo ""
echo "4. Prevents:"
echo "   - Race conditions in file operations"
echo "   - Database migration collisions"
echo "   - Build artifact corruption"
echo "   - Config file overwrites"
echo ""
echo "5. The run lock is PER-ID and SHARED across modes:"
echo "   - debounce:build and throttle:build share the same run lock"
echo "   - They will never execute simultaneously"
echo ""
