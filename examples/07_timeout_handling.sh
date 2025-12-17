#!/usr/bin/env bash
#
# EXAMPLE 07: Timeout Handling
# ============================
#
# This example demonstrates pacer's --timeout option, which kills commands
# that run longer than a specified duration.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# Long-running or hung commands can block the pacer queue indefinitely:
#
#   - Network requests that hang (API timeout, DNS issues)
#   - Build commands that get stuck
#   - Git operations waiting on network
#   - Any I/O operation that could block forever
#
# Without timeout protection, a single hung command blocks ALL subsequent
# executions for that ID - the run lock is held forever.
#
# WHAT PACER PROVIDES:
# --------------------
# 1. --timeout <ms>: Maximum execution time in milliseconds
# 2. Automatic SIGTERM then SIGKILL if command exceeds timeout
# 3. Exit code 79 indicates timeout occurred
# 4. Releases the run lock so subsequent calls can proceed
#
# HOW IT WORKS:
# -------------
# 1. Pacer spawns your command in a background process
# 2. Polls every 100ms to check if command finished
# 3. If elapsed time exceeds timeout_ms:
#    - Sends SIGTERM to command
#    - Waits 100ms
#    - Sends SIGKILL if still running
# 4. Returns exit code 79
#
# EXIT CODE 79:
# -------------
# When you see exit code 79, you know:
#   - The command was started
#   - It exceeded the timeout
#   - It was forcibly killed
#   - You may need to handle cleanup (partial writes, locks, etc.)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Timeout Handling ==="
echo ""
echo "The --timeout option kills commands that run too long."
echo "Exit code 79 = command was killed due to timeout."
echo ""

# Cleanup
"$PACER" --reset-all demo-timeout 2>/dev/null || true

echo "SCENARIO 1: Command Completes Within Timeout"
echo "---------------------------------------------"
echo "Running a 500ms command with 2000ms timeout..."
echo ""

"$PACER" --timeout 2000 demo-timeout 100 \
    bash -c 'echo "[$(date +%H:%M:%S.%3N)] Starting quick command..."; sleep 0.5; echo "[$(date +%H:%M:%S.%3N)] Completed!"'

exit_code=$?
echo ""
echo "Exit code: $exit_code (0 = success)"
echo ""

"$PACER" --reset-all demo-timeout 2>/dev/null || true
sleep 0.1

echo "SCENARIO 2: Command Exceeds Timeout (Gets Killed)"
echo "--------------------------------------------------"
echo "Running a 5s command with 1000ms timeout..."
echo ""

set +e  # Don't exit on error
"$PACER" --timeout 1000 demo-timeout 100 \
    bash -c 'echo "[$(date +%H:%M:%S.%3N)] Starting slow command (5 seconds)..."; sleep 5; echo "[$(date +%H:%M:%S.%3N)] This should NOT print!"'

exit_code=$?
set -e
echo ""
echo "Exit code: $exit_code (79 = killed due to timeout)"
echo ""

"$PACER" --reset-all demo-timeout 2>/dev/null || true
sleep 0.1

echo "SCENARIO 3: Handling Timeout in Scripts"
echo "---------------------------------------"
echo "Demonstrating how to handle timeout exit code in your scripts..."
echo ""

cat << 'SCRIPT'
# Example script pattern for handling timeouts:

pacer --timeout 5000 api-call 1000 curl https://api.example.com/slow-endpoint
case $? in
    0)   echo "Success!" ;;
    79)  echo "Timeout! API took too long - using cached data" ;;
    77)  echo "Queued - another request is pending" ;;
    *)   echo "Other error" ;;
esac
SCRIPT

echo ""

# Demonstrate the pattern
echo "Running demonstration..."
echo ""

set +e
"$PACER" --timeout 500 demo-timeout 100 \
    bash -c 'sleep 1'
exit_code=$?
set -e

case $exit_code in
    0)   echo "Result: Success (command completed)" ;;
    79)  echo "Result: Timeout (exit code 79) - command was killed" ;;
    77)  echo "Result: Queued (exit code 77)" ;;
    *)   echo "Result: Exit code $exit_code" ;;
esac

echo ""

"$PACER" --reset-all demo-timeout 2>/dev/null || true

echo "SCENARIO 4: Timeout with Throttle (Rate-Limited API)"
echo "-----------------------------------------------------"
echo "Combining --timeout with --throttle for API rate limiting..."
echo ""

echo "Pattern: Rate limit API calls AND prevent hung requests"
echo ""
echo '  pacer --throttle --timeout 5000 api 1000 curl https://api.example.com'
echo ""
echo "This ensures:"
echo "  - At most 1 API call per second (throttle 1000ms)"
echo "  - Each call times out after 5 seconds"
echo "  - Hung requests don't block the queue"
echo ""

# Demonstrate with simulated API calls
echo "Simulating 3 API calls with 800ms timeout, 500ms throttle..."
echo ""

for i in 1 2 3; do
    echo "[$(date '+%H:%M:%S.%3N')] API call $i..."
    set +e
    if ((i == 2)); then
        # Second call simulates a slow API
        "$PACER" --throttle --timeout 800 demo-timeout 500 \
            bash -c "echo '  Processing (will timeout)...'; sleep 2; echo '  Should not print'" &
    else
        "$PACER" --throttle --timeout 800 demo-timeout 500 \
            bash -c "echo '  Processing...'; sleep 0.3; echo '  Done!'" &
    fi
    set -e
    sleep 0.6
done

wait
echo ""

# Cleanup
"$PACER" --reset-all demo-timeout 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. --timeout <ms>: Maximum execution time in milliseconds"
echo ""
echo "2. Exit code 79: Command was killed due to timeout"
echo "   - Distinguishes timeout from other errors"
echo "   - Lets your scripts handle timeouts gracefully"
echo ""
echo "3. How timeout is enforced:"
echo "   - SIGTERM sent first (allows graceful shutdown)"
echo "   - SIGKILL sent 100ms later if still running"
echo "   - Run lock is released (queue unblocked)"
echo ""
echo "4. COMMON USE CASES:"
echo "   - API calls: Prevent hung network requests"
echo "   - Build commands: Fail fast on stuck builds"
echo "   - Git operations: Don't hang on network issues"
echo "   - External processes: Any potentially slow operation"
echo ""
echo "5. COMBINE with modes:"
echo "   - pacer --timeout 5000 build 500 make"
echo "   - pacer --throttle --timeout 5000 api 1000 curl ..."
echo "   - pacer --debounce --timeout 10000 sync 2000 rsync ..."
echo ""
