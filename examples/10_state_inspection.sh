#!/usr/bin/env bash
#
# EXAMPLE 10: State Inspection and Management
# ===========================================
#
# This example demonstrates pacer's operational commands for inspecting
# and managing state: --status, --reset, and --reset-all.
#
# WHY STATE INSPECTION MATTERS:
# -----------------------------
# When debugging timing issues or troubleshooting stuck commands:
#   - Is there a runner currently active?
#   - When was the last execution?
#   - What command is pending?
#   - How long has the runner been running?
#
# WHAT PACER PROVIDES:
# --------------------
# 1. --status [mode id]: Show state for specific key or all keys
# 2. --reset <mode> <id>: Kill runner and clear state for one mode
# 3. --reset-all <id>: Reset both debounce and throttle for an ID
#
# STATE INFORMATION:
# ------------------
# - KEY: The mode:id identifier (e.g., "debounce:build")
# - ALIVE: Is the runner process still running?
# - PID: Runner process ID
# - LAST_EXEC_MS: Timestamp of last execution (epoch ms)
# - NEXT_AT_MS: When next execution is scheduled (debounce: deadline, throttle: window_end)
# - NEXT_IN_MS: Milliseconds until next execution
# - DIRTY: (throttle only) Is there a pending trailing execution?
# - AGE_MS: How long since runner started
# - CMD: The pending command to execute
#
# DEBUGGING WITH PACER_DEBUG:
# ---------------------------
# Set PACER_DEBUG=1 to enable verbose logging:
#   - Decision-making: why a call queued vs executed
#   - Timing: deadline updates, window calculations
#   - Coordination: smart skip detection, lock acquisition
#
# Set PACER_LOG_FILE=/path to log to file instead of stderr.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: State Inspection and Management ==="
echo ""

# Clean start
"$PACER" --reset-all demo-state 2>/dev/null || true

echo "1. VIEW STATE: --status"
echo "========================"
echo ""
echo "First, let's see that there's no state (fresh start):"
echo ""
echo '$ pacer --status'
"$PACER" --status
echo ""

echo "Now let's create some pending state by starting a debounce:"
echo ""

# Start a slow command that will keep runner alive
"$PACER" demo-state 2000 bash -c 'sleep 3; echo "Done!"' &
sleep 0.2

echo "State after starting a debounced operation:"
echo ""
echo '$ pacer --status'
"$PACER" --status
echo ""

echo "Column explanations:"
echo "  KEY:          mode:id identifier"
echo "  ALIVE:        'yes' if runner process is running"
echo "  PID:          Runner process ID"
echo "  LAST_EXEC_MS: Epoch milliseconds of last execution"
echo "  NEXT_AT_MS:   When execution is scheduled (deadline/window)"
echo "  NEXT_IN_MS:   Milliseconds until scheduled execution"
echo "  DIRTY:        Throttle: pending trailing execution ('1' or '0')"
echo "  AGE_MS:       How long since runner started"
echo "  CMD:          The command that will execute"
echo ""

echo "View specific key state:"
echo ""
echo '$ pacer --status debounce demo-state'
"$PACER" --status debounce demo-state 2>&1 || true
echo ""

# Wait for background to settle
wait 2>/dev/null || true
sleep 0.5

echo "2. RESET STATE: --reset"
echo "========================"
echo ""
echo "Let's start another operation and then reset it:"
echo ""

# Start a long-running command
"$PACER" demo-state 5000 bash -c 'echo "Starting long task..."; sleep 10; echo "Finished!"' &
sleep 0.3

echo "State before reset:"
"$PACER" --status 2>&1 | head -5
echo ""

echo "Resetting debounce:demo-state..."
echo '$ pacer --reset debounce demo-state'
"$PACER" --reset debounce demo-state 2>&1 || true
echo ""

echo "State after reset:"
"$PACER" --status 2>&1 | head -5
echo ""

wait 2>/dev/null || true

echo "3. RESET ALL MODES: --reset-all"
echo "================================"
echo ""
echo "When using both debounce and throttle with the same ID,"
echo "--reset-all clears both:"
echo ""

# Create state in both modes
"$PACER" --debounce demo-state 2000 bash -c 'echo "debounce"' &
"$PACER" --throttle demo-state 200 bash -c 'echo "throttle"' &
sleep 0.3

echo "State with both modes active:"
"$PACER" --status 2>&1 | grep -E "^(KEY|---|-|debounce:demo|throttle:demo)" || true
echo ""

echo "Reset all modes for ID 'demo-state':"
echo '$ pacer --reset-all demo-state'
"$PACER" --reset-all demo-state
echo ""

echo "State after --reset-all:"
"$PACER" --status 2>&1 | head -5
echo ""

wait 2>/dev/null || true

echo "4. DEBUG LOGGING: PACER_DEBUG"
echo "=============================="
echo ""
echo "Enable verbose logging to see pacer's decision-making:"
echo ""

echo "Example output with PACER_DEBUG=1:"
echo ""

export PACER_DEBUG=1
"$PACER" --reset-all demo-debug 2>/dev/null || true

# Show sample debug output
{
    "$PACER" demo-debug 300 echo "first call"
    sleep 0.1
    "$PACER" demo-debug 300 echo "second call"
    sleep 0.1
    "$PACER" demo-debug 300 echo "third call"
    wait
} 2>&1 | head -20

unset PACER_DEBUG
echo ""

echo "Debug log fields:"
echo "  [HH:MM:SS] [pacer:level] message"
echo ""
echo "  Levels: info, warn, error"
echo "  Shows: lock acquisition, timing decisions, execution, smart skip"
echo ""

"$PACER" --reset-all demo-debug 2>/dev/null || true

echo "5. LOGGING TO FILE: PACER_LOG_FILE"
echo "==================================="
echo ""
echo "For background processes, log to a file:"
echo ""
cat << 'EXAMPLE'
   export PACER_DEBUG=1
   export PACER_LOG_FILE=/tmp/pacer.log

   # Now pacer writes debug info to file instead of stderr
   pacer build 500 make  # Logs go to /tmp/pacer.log

   # View logs
   tail -f /tmp/pacer.log
EXAMPLE
echo ""

# Demonstrate
export PACER_DEBUG=1
export PACER_LOG_FILE="/tmp/pacer-demo.log"
rm -f "$PACER_LOG_FILE"

"$PACER" demo-log 200 echo "test" &
sleep 0.3
wait 2>/dev/null || true

echo "Sample log file contents:"
head -5 "$PACER_LOG_FILE" 2>/dev/null || echo "(no log output)"
echo ""

unset PACER_DEBUG
unset PACER_LOG_FILE
rm -f /tmp/pacer-demo.log

# Final cleanup
"$PACER" --reset-all demo-state 2>/dev/null || true
"$PACER" --reset-all demo-debug 2>/dev/null || true
"$PACER" --reset-all demo-log 2>/dev/null || true

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                           KEY TAKEAWAYS                              ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "STATE INSPECTION:"
echo "  pacer --status                    # Show all state"
echo "  pacer --status debounce build     # Show specific key"
echo ""
echo "STATE MANAGEMENT:"
echo "  pacer --reset debounce build      # Reset one mode"
echo "  pacer --reset-all build           # Reset both modes for ID"
echo ""
echo "DEBUG LOGGING:"
echo "  PACER_DEBUG=1 pacer ...           # Log to stderr"
echo "  PACER_LOG_FILE=/tmp/p.log ...     # Log to file"
echo ""
echo "TROUBLESHOOTING COMMON ISSUES:"
echo ""
echo "  Command not running?"
echo "    → Check --status: Is ALIVE=yes? Is NEXT_IN_MS reasonable?"
echo "    → Enable PACER_DEBUG to see timing decisions"
echo ""
echo "  Too many executions?"
echo "    → Check delay_ms: Maybe too short?"
echo "    → Check mode: Throttle runs more often than debounce"
echo ""
echo "  Stuck/hung runner?"
echo "    → Use --reset or --reset-all to clear state"
echo "    → Add --timeout to kill slow commands"
echo ""
echo "  Debugging production issues?"
echo "    → Set PACER_LOG_FILE to capture logs without stderr noise"
echo "    → Use --status periodically to monitor state"
echo ""
