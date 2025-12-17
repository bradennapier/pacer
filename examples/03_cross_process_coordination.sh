#!/usr/bin/env bash
#
# EXAMPLE 03: Cross-Process Coordination
# =======================================
#
# This example demonstrates pacer's KEY DIFFERENTIATOR: coordination across
# SEPARATE PROCESSES. Unlike in-process libraries (TanStack Pacer, lodash),
# pacer coordinates shell invocations that have no shared memory.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# Event sources like file watchers, window managers, and system signals spawn
# SEPARATE processes for each event. Traditional debounce/throttle libraries
# only work within a single process's memory.
#
# Example: fswatch spawns a new shell for each file change event. Each shell
# has no idea about the others. Without cross-process coordination, each
# would run your build command separately.
#
# WHY THIS IS HARD:
# -----------------
# In-process solutions (JavaScript, Python libraries) use variables/closures
# to track state. But when events come from:
#   - File watcher callbacks (each is a new process)
#   - Window manager signals (yabai, skhd - new process per event)
#   - Cron jobs or launchd
#   - Separate terminal sessions
#
# There's no shared memory. You need FILESYSTEM-BASED coordination.
#
# WHAT PACER PROVIDES:
# --------------------
# 1. Filesystem-based state in /tmp/pacer/
# 2. File locking with flock for atomic operations
# 3. State files track timing, commands, and process IDs
# 4. Any shell invocation can participate in the coordination
#
# HOW IT WORKS:
# -------------
# 1. Each pacer call acquires a state lock (per mode:id)
# 2. Reads/updates timing state from filesystem
# 3. If it should run, acquires a shared run lock (per id)
# 4. Writes latest command to a file (NUL-delimited for safety)
# 5. Spawns or defers to existing runner process
#
# STATE FILES:
# ------------
# /tmp/pacer/
#   <mode>:<id>.state.lock     # Serializes decision-making
#   <id>.run.lock              # Shared single-flight lock
#   <id>.last_exec_ms          # Last execution timestamp
#   <mode>:<id>.pending_pid    # Runner process ID
#   <mode>:<id>.cmd            # Command to execute (NUL-delimited)
#   ...
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Cross-Process Coordination ==="
echo ""
echo "This demonstrates pacer's key advantage over in-process libraries:"
echo "SEPARATE shell invocations coordinate through the filesystem."
echo ""

# Clean up
"$PACER" --reset-all demo-cross 2>/dev/null || true
rm -f /tmp/cross-process-demo.log 2>/dev/null || true

echo "SCENARIO: Simulating File Watcher Events"
echo "-----------------------------------------"
echo "File watchers (fswatch, inotify) spawn a NEW process for each event."
echo "We'll simulate 10 rapid file change events in separate subshells."
echo ""
echo "WITHOUT pacer: 10 separate build commands would run"
echo "WITH pacer: Debounced to 1 execution"
echo ""

# Create a log file to track activity across processes
LOG_FILE="/tmp/cross-process-demo.log"
touch "$LOG_FILE"

# The command that would run (e.g., a build command)
# Each call logs which "event" triggered it and its PID
echo "Starting simulation..."
echo ""

# Spawn 10 COMPLETELY SEPARATE subshells (simulating file watcher events)
# Each is an independent process with no shared memory
for i in {1..10}; do
    # This subshell simulates a file watcher callback - completely isolated
    (
        # Each subshell has its own PID and environment
        event_pid=$$
        echo "[$(date '+%H:%M:%S.%3N')] Event $i (PID: $event_pid) - calling pacer..."

        # The ONLY coordination happens through pacer's filesystem state
        "$PACER" demo-cross 500 bash -c "
            echo \"[$(date '+%H:%M:%S.%3N')] BUILD EXECUTED (triggered by event $i)\" >> '$LOG_FILE'
            echo \"[$(date '+%H:%M:%S.%3N')] BUILD EXECUTED (triggered by event $i)\"
        "

        exit_code=$?
        case $exit_code in
            0)  echo "[$(date '+%H:%M:%S.%3N')] Event $i result: EXECUTED (ran the command)" ;;
            77) echo "[$(date '+%H:%M:%S.%3N')] Event $i result: QUEUED (another runner will handle it)" ;;
            *)  echo "[$(date '+%H:%M:%S.%3N')] Event $i result: Exit code $exit_code" ;;
        esac
    ) &

    # Slight delay between events (simulating rapid but not instant file changes)
    sleep 0.05
done

echo ""
echo "Waiting for all events and execution to complete..."
wait
sleep 0.6  # Wait for debounced execution

echo ""
echo "=== Results ==="
echo ""
echo "Events sent: 10 (in 10 separate processes)"
echo "Build executions (from log file):"
cat "$LOG_FILE" 2>/dev/null || echo "  (none)"
echo ""
exec_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
echo "Total executions: $exec_count"
echo ""

# Show the coordination mechanism
echo "=== How It Works ==="
echo ""
echo "Pacer uses filesystem-based state in /tmp/pacer/:"
echo ""
ls -la /tmp/pacer/debounce:demo-cross* /tmp/pacer/demo-cross* 2>/dev/null || echo "  (state files cleaned up)"
echo ""

# Cleanup
"$PACER" --reset-all demo-cross 2>/dev/null || true
rm -f "$LOG_FILE" 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. CROSS-PROCESS coordination is pacer's key differentiator"
echo "2. Uses filesystem state (/tmp/pacer/) - no shared memory needed"
echo "3. Each pacer call is a SEPARATE process - they coordinate via files"
echo "4. Exit codes tell you what happened:"
echo "   - 0:  Your command executed"
echo "   - 77: Queued - another runner is handling it"
echo "   - 76: Skipped (--no-wait mode)"
echo ""
echo "5. File locking (flock) ensures atomic state updates"
echo ""
echo "WHY THIS MATTERS:"
echo "  In-process libraries (lodash.debounce, TanStack Pacer in JS) require"
echo "  the debounce wrapper to live in the SAME process as events."
echo ""
echo "  But shell events come from SEPARATE processes:"
echo "    - fswatch callbacks"
echo "    - yabai/skhd signal handlers"
echo "    - launchd/cron jobs"
echo "    - Docker event listeners"
echo ""
echo "  Pacer bridges this gap with filesystem-based coordination."
echo ""
