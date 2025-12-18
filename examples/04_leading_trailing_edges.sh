#!/usr/bin/env bash
#
# EXAMPLE 04: Leading and Trailing Edge Control
# ==============================================
#
# This example demonstrates pacer's --leading and --trailing options,
# which control WHEN your command executes relative to the burst of events.
#
# THE CONCEPT:
# ------------
#
# Events form a "burst" - a cluster of rapid calls followed by quiet:
#
#   Events:  x  x  x  x  x                    x  x
#            |--|--|--|--|-----|              |--|-----|
#            ^                 ^              ^        ^
#            LEADING edge      TRAILING edge  LEADING  TRAILING
#            (start of burst)  (end of burst)
#
# LEADING EDGE (--leading true|false):
# ------------------------------------
# - true:  Execute IMMEDIATELY on the first call
# - false: Wait for the delay to expire before executing
#
# TRAILING EDGE (--trailing true|false):
# --------------------------------------
# - true:  Execute after the delay/window expires (captures final state)
# - false: No execution at the end
#
# COMMON COMBINATIONS:
# --------------------
# | leading | trailing | Behavior                        | Use Cases                    |
# |---------|----------|---------------------------------|------------------------------|
# | false   | true     | Wait for quiet, then act        | Search, auto-save, config    |
# | true    | true     | Act now AND after quiet         | Form validation, preview     |
# | true    | false    | Act once, ignore rest           | Button clicks, notifications |
# | false   | false    | Never runs (don't use this)     | -                            |
#
# DEBOUNCE DEFAULTS: --leading false --trailing true
# THROTTLE DEFAULTS: --leading true  --trailing true
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Leading and Trailing Edge Control ==="
echo ""

# Helper function
demo_exec() {
    echo "    >>> [$(date '+%H:%M:%S.%3N')] EXECUTED: $1"
}
export -f demo_exec

# Cleanup function
cleanup() {
    "$PACER" --reset-all demo-edge 2>/dev/null || true
}
trap cleanup EXIT

#------------------------------------------------------------------------------
# DEBOUNCE EXAMPLES
#------------------------------------------------------------------------------

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                         DEBOUNCE EXAMPLES                            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "1. DEBOUNCE: --leading false --trailing true (DEFAULT)"
echo "   Wait for silence, then act with final state"
echo "   ─────────────────────────────────────────────"
cleanup

echo "[$(date '+%H:%M:%S.%3N')] Sending 5 rapid calls..."
for i in 1 2 3 4 5; do
    "$PACER" --debounce --leading false --trailing true \
        demo-edge 400 bash -c "demo_exec 'debounce-default-$i'" &
    sleep 0.08
done
wait
sleep 0.5
echo "   Expected: ONE execution after 400ms quiet period"
echo ""

echo "2. DEBOUNCE: --leading true --trailing true"
echo "   Act NOW and again after silence"
echo "   ─────────────────────────────────────────────"
cleanup
sleep 0.1

echo "[$(date '+%H:%M:%S.%3N')] Sending 5 rapid calls..."
for i in 1 2 3 4 5; do
    "$PACER" --debounce --leading true --trailing true \
        demo-edge 400 bash -c "demo_exec 'debounce-both-$i'" &
    sleep 0.08
done
wait
sleep 0.5
echo "   Expected: TWO executions - immediate AND after quiet"
echo ""

echo "3. DEBOUNCE: --leading true --trailing false"
echo "   Act once immediately, ignore the rest"
echo "   ─────────────────────────────────────────────"
cleanup
sleep 0.1

echo "[$(date '+%H:%M:%S.%3N')] Sending 5 rapid calls..."
for i in 1 2 3 4 5; do
    "$PACER" --debounce --leading true --trailing false \
        demo-edge 400 bash -c "demo_exec 'debounce-leading-$i'" &
    sleep 0.08
done
wait
sleep 0.5
echo "   Expected: ONE execution immediately (no trailing)"
echo ""

#------------------------------------------------------------------------------
# THROTTLE EXAMPLES
#------------------------------------------------------------------------------

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                         THROTTLE EXAMPLES                            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "4. THROTTLE: --leading true --trailing true (DEFAULT)"
echo "   Act now, then at intervals, then final"
echo "   ─────────────────────────────────────────────"
cleanup
sleep 0.1

echo "[$(date '+%H:%M:%S.%3N')] Sending 8 rapid calls over ~400ms..."
for i in 1 2 3 4 5 6 7 8; do
    "$PACER" --throttle --leading true --trailing true \
        demo-edge 200 bash -c "demo_exec 'throttle-default-$i'" &
    sleep 0.05
done
wait
sleep 0.3
echo "   Expected: Multiple executions at ~200ms intervals"
echo ""

echo "5. THROTTLE: --leading true --trailing false"
echo "   Act now, then at intervals only (drop trailing)"
echo "   ─────────────────────────────────────────────"
cleanup
sleep 0.1

echo "[$(date '+%H:%M:%S.%3N')] Sending 8 rapid calls over ~400ms..."
for i in 1 2 3 4 5 6 7 8; do
    "$PACER" --throttle --leading true --trailing false \
        demo-edge 200 bash -c "demo_exec 'throttle-no-trail-$i'" &
    sleep 0.05
done
wait
sleep 0.3
echo "   Expected: Executions at intervals, but NO final trailing execution"
echo ""

echo "6. THROTTLE: --leading false --trailing true"
echo "   Wait for interval, capture final state"
echo "   ─────────────────────────────────────────────"
cleanup
sleep 0.1

echo "[$(date '+%H:%M:%S.%3N')] Sending 8 rapid calls over ~400ms..."
for i in 1 2 3 4 5 6 7 8; do
    "$PACER" --throttle --leading false --trailing true \
        demo-edge 200 bash -c "demo_exec 'throttle-no-lead-$i'" &
    sleep 0.05
done
wait
sleep 0.3
echo "   Expected: NO immediate execution, only at window ends"
echo ""

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                           KEY TAKEAWAYS                              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "DEBOUNCE USE CASES:"
echo "  --leading false --trailing true  (default)"
echo "      Search input, auto-save, config reload"
echo "      → Wait for user to stop, then act with final state"
echo ""
echo "  --leading true --trailing true"
echo "      Form validation, live preview"
echo "      → Instant feedback + final state check"
echo ""
echo "  --leading true --trailing false"
echo "      Button clicks, notifications"
echo "      → Act once, ignore duplicates during cooldown"
echo ""
echo "THROTTLE USE CASES:"
echo "  --leading true --trailing true  (default)"
echo "      Scroll/drag UI, live metrics"
echo "      → Instant feedback + steady updates + final position"
echo ""
echo "  --leading true --trailing false"
echo "      Rate limiting, progress polling"
echo "      → Fixed frequency, drop trailing"
echo ""
echo "  --leading false --trailing true"
echo "      Batch processing, aggregation"
echo "      → Collect events, process at window end"
echo ""
