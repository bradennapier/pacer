#!/usr/bin/env bash
#
# EXAMPLE 02: Basic Throttle
# ==========================
#
# This example demonstrates pacer's THROTTLE mode - enforcing a maximum frequency
# with FIXED time windows. Unlike debounce, the timer NEVER resets.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# During continuous activity (scrolling, dragging, streaming data), you want
# PERIODIC updates, not silence-then-burst like debounce. Throttle gives you
# a steady heartbeat of executions.
#
# Example: During a long scroll, you want position updates every 100ms - not
# waiting until the user stops scrolling.
#
# KEY DIFFERENCE FROM DEBOUNCE:
# -----------------------------
#                     DEBOUNCE              THROTTLE
# Timer resets?       Yes, every call       No, fixed windows
# During burst:       Waits indefinitely    Fires at intervals
# After burst:        Fires once            Fires once (if trailing)
#
# WHAT PACER PROVIDES:
# --------------------
# 1. Fixed time windows - timer NEVER resets
# 2. Leading edge execution - run immediately on first call (default)
# 3. Trailing edge execution - run again after window if calls arrived
# 4. Cross-process coordination - separate invocations coordinate
# 5. Last-call-wins - always uses most recent arguments
#
# HOW IT WORKS (default --leading true --trailing true):
# ------------------------------------------------------
# 1. First call triggers IMMEDIATE execution (leading edge)
# 2. Opens a time window of delay_ms
# 3. Subsequent calls during window are coalesced (latest args kept)
# 4. At window end, if calls arrived, execute again (trailing edge)
# 5. Process repeats if activity continues
#
# TIMELINE VISUALIZATION:
# -----------------------
# Events:  x  x  x  x  x  x  x  x  x  x      (10 rapid calls over 500ms)
#          ▼--|--|--|--|--▼--|--|--|--|--▼   (executes at 0ms, 200ms, 400ms, ~500ms)
#          [window 1]     [window 2]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Basic Throttle ==="
echo ""
echo "Throttle guarantees a maximum execution frequency."
echo "The timer NEVER resets - fixed time windows."
echo ""

# Clean up any existing state
"$PACER" --reset-all demo-throttle 2>/dev/null || true

# demo_command echoes a timestamped execution message that shows the received argument.
demo_command() {
    echo "[$(date '+%H:%M:%S.%3N')] >>> EXECUTED with arg: $1"
}
export -f demo_command

echo "SCENARIO 1: Rapid calls with 300ms throttle window"
echo "---------------------------------------------------"
echo "Sending 10 calls as fast as possible over ~500ms..."
echo "Throttle window: 300ms"
echo ""
echo "Expected behavior:"
echo "  - First call executes IMMEDIATELY (leading edge)"
echo "  - Calls during 300ms window are coalesced"
echo "  - At window end, execute with latest args (trailing edge)"
echo "  - Repeat for next window..."
echo ""

echo "[$(date '+%H:%M:%S.%3N')] Starting rapid calls..."
echo ""

# Fire 10 rapid calls - throttle will limit to ~3-4 executions
for i in {1..10}; do
    echo "[$(date '+%H:%M:%S.%3N')] Sending call $i..."
    "$PACER" --throttle demo-throttle 300 bash -c "demo_command 'call_$i'" &
    sleep 0.05  # 50ms between calls
done

# Wait for all background jobs and final execution
wait
sleep 0.4

echo ""
echo "RESULT: Notice multiple executions occurred at fixed intervals!"
echo "         Instead of 10 executions, throttle limited it to ~3-4."
echo ""

# Cleanup
"$PACER" --reset-all demo-throttle 2>/dev/null || true
sleep 0.1

echo ""
echo "SCENARIO 2: Spread out calls (each gets its own window)"
echo "-------------------------------------------------------"
echo "Sending 3 calls with 500ms gaps, 300ms throttle window..."
echo "Each call should execute since they're outside each other's window."
echo ""

for i in 1 2 3; do
    echo "[$(date '+%H:%M:%S.%3N')] Sending call $i..."
    "$PACER" --throttle demo-throttle 300 bash -c "demo_command 'spread_$i'"
    sleep 0.5  # 500ms gap - outside the 300ms window
done

echo ""
echo "RESULT: Each call executed because they were spaced outside the window."
echo ""

# Cleanup
"$PACER" --reset-all demo-throttle 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. Use --throttle flag for throttle mode"
echo "2. Timer NEVER resets - uses fixed time windows"
echo "3. Default is --leading true --trailing true:"
echo "   - Execute immediately on first call"
echo "   - Execute again at window end if calls arrived"
echo "4. Provides STEADY UPDATES during continuous activity"
echo "5. Last-call-wins - trailing execution uses latest args"
echo ""
echo "COMMON USE CASES:"
echo "  - Scroll/drag position updates"
echo "  - Live metrics/telemetry sampling"
echo "  - Progress bar updates"
echo "  - Rate-limiting API calls"
echo "  - Status bar refresh during window manager events"
echo ""
echo "COMPARISON:"
echo "  10 rapid events over 500ms, delay=200ms:"
echo "    DEBOUNCE: Fires ONCE at 700ms (after quiet)"
echo "    THROTTLE: Fires at 0ms, 200ms, 400ms, ~500ms (steady beat)"
echo ""