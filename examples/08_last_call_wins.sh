#!/usr/bin/env bash
#
# EXAMPLE 08: Last-Call-Wins Arguments
# =====================================
#
# This example demonstrates pacer's LAST-CALL-WINS behavior: when multiple
# calls arrive during a delay/window, the FINAL call's arguments are used.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# When debouncing/throttling, you typically want the MOST RECENT state:
#
#   - User types "app" then "apple" - you want to search for "apple"
#   - File watcher sees fileA then fileB - you want the latest file info
#   - Config changes A then B - you want to apply config B
#
# Without last-call-wins, you'd either:
#   - Execute with stale arguments (first-call-wins)
#   - Execute multiple times (no coalescing)
#
# WHAT PACER PROVIDES:
# --------------------
# 1. Each call overwrites the pending command file
# 2. Runner always reads LATEST command before executing
# 3. Arguments are stored NUL-delimited (safe for spaces, quotes, special chars)
# 4. Combined with single-flight: latest args, single execution
#
# HOW IT WORKS:
# -------------
# 1. Call arrives → writes command+args to /tmp/pacer/<mode>:<id>.cmd
# 2. Next call arrives → OVERWRITES the .cmd file with new args
# 3. When runner executes, it reads .cmd file (gets latest)
# 4. NUL-delimited storage ensures special characters are preserved
#
# ARGUMENT SAFETY:
# ----------------
# Pacer handles complex arguments correctly:
#   - Spaces: "hello world"
#   - Quotes: "say 'hello'"
#   - Special chars: "file*.txt"
#   - Empty strings: ""
#   - Newlines: $'line1\nline2'
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Last-Call-Wins Arguments ==="
echo ""
echo "When multiple calls arrive, the FINAL call's arguments are used."
echo "This ensures you always work with the most recent state."
echo ""

# Cleanup
"$PACER" --reset-all demo-lastcall 2>/dev/null || true

# Helper to show what was received
show_args() {
    echo "[$(date '+%H:%M:%S.%3N')] EXECUTED with args:"
    for arg in "$@"; do
        echo "    → '$arg'"
    done
}
export -f show_args

echo "SCENARIO 1: Rapid Calls with Different Arguments"
echo "-------------------------------------------------"
echo "Simulating search input: user types progressively..."
echo ""

# Simulate typing: "a" → "ap" → "app" → "appl" → "apple"
# Only the final "apple" should be used
echo "[$(date '+%H:%M:%S.%3N')] User types 'a'..."
"$PACER" demo-lastcall 400 bash -c 'show_args "search_query" "a"' &

sleep 0.08
echo "[$(date '+%H:%M:%S.%3N')] User types 'ap'..."
"$PACER" demo-lastcall 400 bash -c 'show_args "search_query" "ap"' &

sleep 0.08
echo "[$(date '+%H:%M:%S.%3N')] User types 'app'..."
"$PACER" demo-lastcall 400 bash -c 'show_args "search_query" "app"' &

sleep 0.08
echo "[$(date '+%H:%M:%S.%3N')] User types 'appl'..."
"$PACER" demo-lastcall 400 bash -c 'show_args "search_query" "appl"' &

sleep 0.08
echo "[$(date '+%H:%M:%S.%3N')] User types 'apple' (FINAL)..."
"$PACER" demo-lastcall 400 bash -c 'show_args "search_query" "apple"' &

wait
sleep 0.5

echo ""
echo "RESULT: Only 'apple' was searched - all intermediate states were discarded!"
echo ""

"$PACER" --reset-all demo-lastcall 2>/dev/null || true
sleep 0.1

echo "SCENARIO 2: Arguments with Special Characters"
echo "----------------------------------------------"
echo "Pacer preserves spaces, quotes, and special characters..."
echo ""

# Test various argument edge cases
echo "[$(date '+%H:%M:%S.%3N')] Call 1: Simple args..."
"$PACER" demo-lastcall 300 bash -c 'show_args "simple" "args"' &

sleep 0.05
echo "[$(date '+%H:%M:%S.%3N')] Call 2: Args with spaces..."
"$PACER" demo-lastcall 300 bash -c 'show_args "hello world" "with spaces"' &

sleep 0.05
echo "[$(date '+%H:%M:%S.%3N')] Call 3: Args with 'quotes'..."
"$PACER" demo-lastcall 300 bash -c "show_args \"it's\" \"got 'quotes'\"" &

sleep 0.05
echo "[$(date '+%H:%M:%S.%3N')] Call 4: FINAL - complex args..."
"$PACER" demo-lastcall 300 bash -c 'show_args "path/to/file with spaces.txt" "--flag=value" "arg with \"quotes\""' &

wait
sleep 0.4

echo ""
echo "RESULT: Complex arguments were preserved correctly!"
echo ""

"$PACER" --reset-all demo-lastcall 2>/dev/null || true
sleep 0.1

echo "SCENARIO 3: File Watcher Pattern"
echo "---------------------------------"
echo "Multiple file changes, only process the latest one..."
echo ""

for file in "config.json" "app.ts" "utils.ts" "main.ts" "index.ts"; do
    echo "[$(date '+%H:%M:%S.%3N')] File changed: $file"
    "$PACER" demo-lastcall 400 bash -c "show_args \"file_changed\" \"$file\"" &
    sleep 0.06
done

wait
sleep 0.5

echo ""
echo "RESULT: Only the last file (index.ts) triggered the build!"
echo "(In a real scenario, you might want to rebuild for ANY change,"
echo " but this demonstrates the last-call-wins behavior.)"
echo ""

# Cleanup
"$PACER" --reset-all demo-lastcall 2>/dev/null || true

echo "=== How Arguments Are Stored ==="
echo ""
echo "Pacer uses NUL-delimited storage for safety:"
echo ""
echo "  /tmp/pacer/<mode>:<id>.cmd contains:"
echo "    arg1\\0arg2\\0arg3\\0..."
echo ""
echo "This handles ANY content safely:"
echo "  - Spaces in arguments"
echo "  - Single and double quotes"
echo "  - Special shell characters"
echo "  - Even newlines within arguments"
echo ""

echo "=== Key Takeaways ==="
echo ""
echo "1. LAST-CALL-WINS: Latest arguments always used"
echo "   - Intermediate states are discarded"
echo "   - Only the final call's args matter"
echo ""
echo "2. ARGUMENT SAFETY: NUL-delimited storage"
echo "   - Spaces, quotes, special chars preserved"
echo "   - No shell escaping issues"
echo ""
echo "3. USE CASES:"
echo "   - Search input: Query with final typed text"
echo "   - Auto-save: Save with latest document state"
echo "   - Config reload: Apply final configuration"
echo "   - File watcher: Process most recent change info"
echo ""
echo "4. COMBINED with debounce/throttle:"
echo "   - Timing controls WHEN to execute"
echo "   - Last-call-wins controls WHAT args to use"
echo "   - Together: efficient, correct behavior"
echo ""
