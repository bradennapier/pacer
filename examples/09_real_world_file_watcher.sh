#!/usr/bin/env bash
#
# EXAMPLE 09: Real-World Integration - File Watcher
# ==================================================
#
# This example demonstrates pacer integration with file watching tools,
# one of the most common use cases for debounce/throttle in shell scripts.
#
# THE PROBLEM THIS SOLVES:
# ------------------------
# File watchers generate MANY events for a single logical change:
#
#   "git checkout feature-branch" might trigger:
#     - 50+ file modify events
#     - 10+ file create events
#     - 10+ file delete events
#     - All within milliseconds
#
# Without pacer, your build/test/lint command would run 70+ times!
#
# FILE WATCHER TOOLS:
# -------------------
# - fswatch (macOS/Linux) - recommended
# - inotifywait (Linux)
# - watchman (Facebook's watcher)
# - nodemon, chokidar-cli (Node.js ecosystem)
#
# WHY PACER IS ESSENTIAL HERE:
# ----------------------------
# File watchers spawn a NEW PROCESS for each event. In-process debounce
# libraries (lodash, TanStack in JS) can't help because each event handler
# is a separate shell invocation with no shared memory.
#
# Pacer's filesystem-based coordination is PERFECT for this use case.
#
# COMMON PATTERNS:
# ----------------
# 1. Build on source change: pacer build 500 make
# 2. Test on save: pacer test 300 npm test
# 3. Lint after edits: pacer lint 200 eslint .
# 4. Compile assets: pacer sass 300 sass src/:dist/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACER="${SCRIPT_DIR}/../pacer"

echo "=== Pacer Example: Real-World File Watcher Integration ==="
echo ""
echo "This example shows how pacer integrates with file watching tools"
echo "to handle rapid file system events efficiently."
echo ""

# Create a demo project directory
DEMO_DIR="/tmp/pacer-filewatcher-demo"
rm -rf "$DEMO_DIR"
mkdir -p "$DEMO_DIR/src"

# Track builds
BUILD_LOG="$DEMO_DIR/build.log"
touch "$BUILD_LOG"

# Cleanup
"$PACER" --reset-all demo-build 2>/dev/null || true

# do_build logs timestamped BUILD STARTED and BUILD COMPLETED entries to BUILD_LOG to simulate a short build run.
do_build() {
    echo "[$(date '+%H:%M:%S.%3N')] BUILD STARTED" | tee -a "$BUILD_LOG"
    sleep 0.5  # Simulate build time
    echo "[$(date '+%H:%M:%S.%3N')] BUILD COMPLETED" | tee -a "$BUILD_LOG"
}
export -f do_build
export BUILD_LOG

echo "DEMO: Simulated File Watcher Events"
echo "------------------------------------"
echo ""
echo "We'll simulate what happens during a git checkout or large paste:"
echo "  - 20 rapid file change events over ~1 second"
echo "  - Each event triggers pacer (like a file watcher would)"
echo "  - Pacer debounces to a single build"
echo ""

echo "Creating demo project files..."
for i in {1..10}; do
    echo "// Source file $i" > "$DEMO_DIR/src/file$i.ts"
done
echo ""

echo "Simulating rapid file changes (like git checkout)..."
echo ""

# Simulate rapid file watcher events
for i in {1..20}; do
    # Modify a file (simulating file watcher detecting change)
    file_num=$((i % 10 + 1))
    echo "// Modified at $(date '+%H:%M:%S.%3N')" >> "$DEMO_DIR/src/file$file_num.ts"

    echo "[$(date '+%H:%M:%S.%3N')] Event: src/file$file_num.ts changed"

    # This is what your file watcher callback would do:
    # Instead of running "make" directly, wrap it with pacer
    "$PACER" demo-build 500 bash -c 'do_build' &

    sleep 0.05  # 50ms between events (typical for git checkout)
done

echo ""
echo "Waiting for debounce timer (500ms after last event)..."
wait
sleep 0.6

echo ""
echo "=== Build Log ==="
cat "$BUILD_LOG"
echo ""

build_count=$(grep -c "BUILD STARTED" "$BUILD_LOG" || echo "0")
echo "File events: 20"
echo "Build executions: $build_count"
echo ""

if [[ "$build_count" -le 2 ]]; then
    echo "SUCCESS! Debounce reduced 20 events to $build_count build(s)."
else
    echo "More builds than expected - timing may vary on this system."
fi

echo ""

#------------------------------------------------------------------------------
# REFERENCE: File Watcher Integration Patterns
#------------------------------------------------------------------------------

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║              FILE WATCHER INTEGRATION PATTERNS                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "1. FSWATCH (macOS/Linux) - Recommended"
echo "   ────────────────────────────────────"
cat << 'PATTERN1'
   # Basic: rebuild on source changes
   fswatch -0 ./src | xargs -0 -n1 -I{} pacer build 500 make

   # With specific extensions
   fswatch -0 -e ".*" -i "\\.ts$" ./src | \
       xargs -0 -n1 -I{} pacer build 500 npm run build

   # Multiple directories
   fswatch -0 ./src ./lib ./config | \
       xargs -0 -n1 -I{} pacer rebuild 1000 ./scripts/rebuild.sh
PATTERN1
echo ""

echo "2. INOTIFYWAIT (Linux)"
echo "   ────────────────────"
cat << 'PATTERN2'
   # Watch for modifications
   inotifywait -m -e modify ./src | while read; do
       pacer build 500 make
   done

   # Recursive with specific events
   inotifywait -m -r -e modify,create,delete ./src | while read; do
       pacer test 300 npm test
   done
PATTERN2
echo ""

echo "3. WHILE-READ Loop Pattern (Universal)"
echo "   ────────────────────────────────────"
cat << 'PATTERN3'
   # Generic pattern for any watcher
   some-watcher ./src | while read event; do
       pacer handle 500 ./process.sh "$event"
   done

   # Sass/CSS compilation
   fswatch ./styles/**/*.scss | while read; do
       pacer sass 300 sass src/:dist/
   done
PATTERN3
echo ""

echo "4. THROTTLE for Progress (During Long Operations)"
echo "   ───────────────────────────────────────────────"
cat << 'PATTERN4'
   # Show progress during long file copies
   rsync -av ./big-dir /backup/ | while read line; do
       pacer --throttle progress 200 ./update-status.sh "$line"
   done
PATTERN4
echo ""

echo "5. COMBINED MODES (Fast + Slow Events)"
echo "   ────────────────────────────────────"
cat << 'PATTERN5'
   # Real use case: webpack-like behavior
   # - Throttle: show "rebuilding..." immediately
   # - Debounce: actual build after changes settle

   fswatch ./src | while read file; do
       pacer --throttle notify 100 echo "Rebuilding..."
       pacer --debounce build 500 make
   done
PATTERN5
echo ""

# Cleanup
rm -rf "$DEMO_DIR"
"$PACER" --reset-all demo-build 2>/dev/null || true

echo "=== Key Takeaways ==="
echo ""
echo "1. FILE WATCHERS generate many events for single logical changes"
echo "   - git checkout: 50+ events"
echo "   - Large paste: 10+ events"
echo "   - IDE save: 2-3 events"
echo ""
echo "2. PACER is essential because file watchers spawn SEPARATE processes"
echo "   - Each event is a new shell invocation"
echo "   - No shared memory for in-process debounce"
echo "   - Pacer coordinates via filesystem state"
echo ""
echo "3. RECOMMENDED SETTINGS:"
echo "   - Build commands: 500-1000ms debounce"
echo "   - Test commands: 300-500ms debounce"
echo "   - Lint commands: 200-300ms debounce"
echo "   - Asset compilation: 300-500ms debounce"
echo ""
echo "4. COMBINE with --timeout to prevent hung builds:"
echo "   pacer --timeout 60000 build 500 make  # 60s max build time"
echo ""