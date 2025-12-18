#!/usr/bin/env bash
#
# EXAMPLE 01: Basic Debounce
# ==========================
#
# This example demonstrates pacer's DEBOUNCE mode - waiting for a "quiet period"
# before executing a command. This is pacer's DEFAULT behavior.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# Without pacer, rapid events (like typing, file changes, resize events) would
# trigger your command dozens of times. You only care about the FINAL state
# after the activity stops.
#
# Example: A user types "hello" quickly. Without debounce, you'd execute 5 times.
# With debounce, you wait until they stop typing, then execute ONCE.
#
# WHAT PACER PROVIDES:
# --------------------
# 1. Timer resets on every call - waits for true "quiet"
# 2. Cross-process coordination - works from separate shell invocations
# 3. Single-flight execution - command never overlaps itself
# 4. Last-call-wins - always uses the most recent arguments
#
# HOW IT WORKS:
# -------------
# 1. Each call to pacer resets a timer (the delay_ms)
# 2. When no new calls arrive for delay_ms milliseconds, the command runs
# 3. If new calls arrive while waiting, the timer resets
# 4. The command always runs with the LATEST arguments provided
#
# TIMELINE VISUALIZATION:
# -----------------------
# Events:  x  x  x  x  x           (5 rapid calls)
#          |--|--|--|--|-----|     (timer keeps resetting)
#                            ▼     (runs ONCE after quiet period)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Basic Debounce ==="
echo ""
echo "Debounce waits for activity to settle before running."
echo "The timer RESETS on every call - so rapid calls delay execution."
echo ""

# Clean up any existing state
"$PACER" --reset-all demo-debounce 2>/dev/null || true

# Helper function that shows what was received
demo_command() {
    echo "[$(date '+%H:%M:%S.%3N')] Command executed with arg: $1"
}
export -f demo_command

echo "SCENARIO 1: Single call (immediate after delay)"
echo "------------------------------------------------"
echo "Sending ONE call with 500ms delay..."
echo ""
"$PACER" demo-debounce 500 bash -c 'demo_command "single"'
echo ""

# Clean up for next test
"$PACER" --reset-all demo-debounce 2>/dev/null || true
sleep 0.1

echo ""
echo "SCENARIO 2: Rapid calls (timer resets each time)"
echo "-------------------------------------------------"
echo "Sending 5 rapid calls with 300ms delay between checks..."
echo "Without pacer: 5 executions. With pacer debounce: 1 execution."
echo ""

# Simulate rapid events - each call resets the 500ms timer
# Note: These are separate invocations, demonstrating CROSS-PROCESS coordination
echo "[$(date '+%H:%M:%S.%3N')] Sending call 1..."
"$PACER" demo-debounce 500 bash -c 'demo_command "call_1"' &

sleep 0.1
echo "[$(date '+%H:%M:%S.%3N')] Sending call 2..."
"$PACER" demo-debounce 500 bash -c 'demo_command "call_2"' &

sleep 0.1
echo "[$(date '+%H:%M:%S.%3N')] Sending call 3..."
"$PACER" demo-debounce 500 bash -c 'demo_command "call_3"' &

sleep 0.1
echo "[$(date '+%H:%M:%S.%3N')] Sending call 4..."
"$PACER" demo-debounce 500 bash -c 'demo_command "call_4"' &

sleep 0.1
echo "[$(date '+%H:%M:%S.%3N')] Sending call 5 (LAST - these args will be used)..."
"$PACER" demo-debounce 500 bash -c 'demo_command "call_5_FINAL"' &

echo ""
echo "Now waiting for the quiet period (500ms after last call)..."
echo ""

# Wait for execution
wait
sleep 0.6

echo ""
echo "RESULT: Notice only ONE execution occurred, with the LAST call's arguments!"
echo ""

# Cleanup
"$PACER" --reset-all demo-debounce 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. DEBOUNCE is the default mode (no --debounce flag needed)"
echo "2. Timer resets on EVERY call - waits for true 'quiet'"
echo "3. Only executes ONCE after activity stops"
echo "4. Uses LAST-CALL-WINS - final arguments are always used"
echo "5. Works CROSS-PROCESS - separate shell invocations coordinate"
echo ""
echo "COMMON USE CASES:"
echo "  - Search input (query after user stops typing)"
echo "  - Auto-save (save after editing pauses)"
echo "  - Config reload (reload after all file writes complete)"
echo "  - Window resize (redraw after resize events settle)"
echo ""
