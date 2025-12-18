#!/usr/bin/env bash
#
# EXAMPLE 06: Cross-Mode Coordination
# ====================================
#
# This example demonstrates pacer's CROSS-MODE COORDINATION: using both
# --debounce and --throttle with the SAME ID, and having them automatically
# coordinate to prevent redundant executions.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# Real-world scenarios often have DIFFERENT event types for the same target:
#
# Example: Refreshing a status bar
#   - Window create/destroy: IMMEDIATE feedback needed (throttle 100ms)
#   - Window title changes: Can fire 100+ times/second, wait for quiet (debounce 1s)
#
# Without coordination:
#   - Throttle runs at t=0ms, t=100ms, t=200ms...
#   - Debounce schedules run for t=1000ms (after title spam quiets)
#   - But throttle already ran at t=100ms! Debounce run is redundant.
#
# WHAT PACER PROVIDES:
# --------------------
# 1. Shared run lock: Same ID never executes simultaneously (any mode)
# 2. Shared last_exec_ms: Both modes track when execution happened
# 3. Smart skip: If one mode executed, the other skips if redundant
#
# HOW SMART SKIP WORKS:
# ---------------------
# When a mode's timer fires, it checks: "Did ANY execution happen since I
# scheduled this?" If yes, the request is already satisfied - skip execution.
#
# Timeline:
#   t=0ms:   throttle fires (executes immediately)
#   t=50ms:  debounce called (schedules for t=1050ms)
#   t=100ms: throttle fires again
#   t=1050ms: debounce timer expires, but sees last_exec was at t=100ms
#            → Request was satisfied, skips execution
#
# REAL-WORLD USE CASE: Window Manager (yabai + sketchybar)
# --------------------------------------------------------
# Different window events need different timing behaviors:
#
#   yabai -m signal --add event=window_created \
#     action="pacer --throttle ui 100 sketchybar --reload"
#
#   yabai -m signal --add event=window_title_changed \
#     action="pacer --debounce ui 1000 sketchybar --reload"
#
# Both use ID "ui" - they coordinate automatically!
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Cross-Mode Coordination ==="
echo ""
echo "Using BOTH --debounce and --throttle with the SAME ID."
echo "They coordinate automatically via smart skip."
echo ""

# Cleanup
"$PACER" --reset-all demo-crossmode 2>/dev/null || true

# Execution log
LOG_FILE="/tmp/crossmode-demo.log"
rm -f "$LOG_FILE"
touch "$LOG_FILE"

# log_exec writes a timestamped execution message with the given label to stdout and appends it to the log file.
log_exec() {
    echo "[$(date '+%H:%M:%S.%3N')] >>> EXECUTED ($1)" | tee -a "$LOG_FILE"
}
export -f log_exec
export LOG_FILE

echo "SCENARIO: Status Bar Refresh with Mixed Event Types"
echo "----------------------------------------------------"
echo ""
echo "Simulating:"
echo "  - Window events (throttle 200ms) - need immediate response"
echo "  - Title change events (debounce 500ms) - wait for spam to settle"
echo ""
echo "Both use ID 'demo-crossmode' - they share the run lock and coordinate."
echo ""

# Enable debug logging to see coordination in action
export PACER_DEBUG=1
export PACER_LOG_FILE="/tmp/pacer-crossmode-debug.log"
rm -f "$PACER_LOG_FILE"

echo "Event timeline:"
echo ""

# t=0: Window created (throttle)
echo "[$(date '+%H:%M:%S.%3N')] EVENT: Window created → throttle call"
"$PACER" --throttle demo-crossmode 200 bash -c "log_exec 'window_created'" &

sleep 0.05

# t=50ms: Title change spam starts (debounce)
for i in 1 2 3 4 5; do
    echo "[$(date '+%H:%M:%S.%3N')] EVENT: Title change $i → debounce call"
    "$PACER" --debounce demo-crossmode 500 bash -c "log_exec 'title_change_$i'" &
    sleep 0.03
done

sleep 0.1

# t=200ms: Another window event (throttle)
echo "[$(date '+%H:%M:%S.%3N')] EVENT: Window destroyed → throttle call"
"$PACER" --throttle demo-crossmode 200 bash -c "log_exec 'window_destroyed'" &

sleep 0.3

# More title spam
for i in 6 7 8; do
    echo "[$(date '+%H:%M:%S.%3N')] EVENT: Title change $i → debounce call"
    "$PACER" --debounce demo-crossmode 500 bash -c "log_exec 'title_change_$i'" &
    sleep 0.03
done

echo ""
echo "Waiting for all timers and executions..."
wait
sleep 0.7  # Wait for debounce trailing

# Disable debug
unset PACER_DEBUG
unset PACER_LOG_FILE

echo ""
echo "=== Execution Log ==="
cat "$LOG_FILE"
echo ""

exec_count=$(wc -l < "$LOG_FILE")
echo "Total executions: $exec_count"
echo ""

echo "=== What Happened ==="
echo ""
echo "Without cross-mode coordination:"
echo "  - Throttle would execute multiple times"
echo "  - Debounce would ALSO execute after 500ms quiet"
echo "  - Many redundant executions!"
echo ""
echo "With pacer's cross-mode coordination:"
echo "  - Throttle executes for immediate window events"
echo "  - Debounce sees throttle already ran, skips redundant execution"
echo "  - Minimal, efficient updates"
echo ""

# Show debug log highlights if it exists
if [[ -f /tmp/pacer-crossmode-debug.log ]]; then
    echo "=== Debug Log Highlights ==="
    echo "(Shows smart skip in action)"
    echo ""
    grep -E "(skipping|EXECUTED|satisfied)" /tmp/pacer-crossmode-debug.log | head -10 || true
    echo ""
fi

# Cleanup
rm -f "$LOG_FILE" /tmp/pacer-crossmode-debug.log
"$PACER" --reset-all demo-crossmode 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. SAME ID across modes = automatic coordination"
echo "   - debounce:myid and throttle:myid share:"
echo "     • Run lock (single-flight across both)"
echo "     • Last execution timestamp (smart skip)"
echo ""
echo "2. SMART SKIP prevents redundant executions:"
echo "   - When a timer fires, pacer checks: 'Has ANY mode executed since'"
echo "     'this timer was scheduled?'"
echo "   - If yes → skip (request already satisfied)"
echo ""
echo "3. USE CASES for mixing modes:"
echo "   - Window manager: throttle for create/destroy, debounce for title"
echo "   - File system: throttle for immediate feedback, debounce for final"
echo "   - UI events: throttle for position updates, debounce for final render"
echo ""
echo "4. TIMING STRATEGY:"
echo "   - Throttle: Events needing immediate feedback (short interval)"
echo "   - Debounce: Events that spam (longer quiet period)"
echo "   - Same command, same ID, different timing behaviors"
echo ""