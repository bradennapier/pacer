# Proposal: `--wait` Flag for Consistent Blocking Behavior

## Problem Statement

Pacer's blocking behavior is inconsistent:

- **Caller becomes runner:** Blocks during delay + command execution
- **Runner already exists:** Returns immediately (exit 77)

This creates confusion because users can't predict whether `pacer build 500 make` will:
- Return in milliseconds (exit 77)
- Block for 500ms+ waiting for debounce
- Block even longer during command execution

## Proposed Solution

**Invert the default:** Make pacer always non-blocking by default, with an explicit `--wait` flag for blocking behavior.

### New Behavior

```bash
# Default: Always returns immediately (runner auto-backgrounds)
pacer build 500 make
echo "Returned immediately, exit code: $?"

# Explicit wait: Block until execution completes
pacer --wait build 500 make
echo "Command finished, exit code: $?"
```

## Implementation Approach

### Option A: Fork Runner to Background

When a caller becomes the runner, instead of entering the runner loop directly:

1. Fork the runner process to background
2. Update `pending_pid` with the child PID
3. Parent returns immediately with a new exit code

```bash
# In pacer script, after "Become runner" decision:

if [[ "$wait_mode" != "true" ]]; then
  # Fork runner to background
  (
    # Child: run the actual runner loop
    _runner_main  # debounce/throttle loop
  ) &
  child_pid=$!
  echo "$child_pid" >"$pend"
  _write_runner_stamp "$runner_stamp" "$child_pid"
  exit 0  # or new exit code indicating "runner spawned"
fi

# If --wait, run inline (current behavior)
_runner_main
```

**Pros:**
- Simple implementation
- Current behavior available via `--wait`
- Consistent UX: always returns quickly

**Cons:**
- Exit code 0 would mean "runner spawned" not "command executed"
- Harder to get command's actual exit code
- Subshell loses some state handling

### Option B: Dedicated Runner Daemon

Spawn a persistent runner daemon that handles all executions:

```bash
# First call spawns daemon, all calls communicate via socket/file
pacer build 500 make  # Returns immediately, daemon handles execution
```

**Pros:**
- True daemon mode, very fast caller return
- Could support status queries, cancellation, etc.

**Cons:**
- Much more complex implementation
- Daemon lifecycle management (startup, shutdown, crashes)
- Overkill for most use cases

### Option C: Hybrid - Background Only Runner Loop

Keep the decision logic inline, but background only the "wait and execute" part:

```bash
# Decision phase: runs inline (fast, ~50ms max)
# Runner loop phase: backgrounds if no --wait

# After becoming runner but before entering runner loop:
if [[ "$wait_mode" != "true" ]]; then
  # Background just the runner loop
  {
    _runner_loop_and_execute
  } &
  runner_bg_pid=$!
  echo "$runner_bg_pid" >"$pend"
  exit 0
fi
```

This is essentially Option A but more clearly structured.

## Recommended: Option A/C with New Exit Codes

```
Exit Codes (proposed):
  0   - Command executed, returns command's exit code (only with --wait)
  1   - Command executed but failed (only with --wait)
  80  - Runner spawned (default mode, non-blocking)
  75  - Busy acquiring lock (transient)
  76  - Skipped (--no-wait mode)
  77  - Queued (runner exists, updated args)
  78  - Bad usage
  79  - Command timeout (only with --wait)
```

Or simpler: always exit 0 for "successfully scheduled" (either spawned runner or queued with existing runner), use `--wait` for actual result.

## New Flag Semantics

```
--wait        Block until execution occurs. If this call becomes the runner,
              wait for the delay + command to complete. If another runner
              exists, wait for that runner's execution to complete.
              Returns the command's exit code.

              Without --wait (default): Return immediately after scheduling.
              Exit 0 if runner spawned, exit 77 if queued with existing runner.
```

### Advanced `--wait` Behavior

If `--wait` is specified and another runner exists:
1. Could exit immediately with 77 (current behavior)
2. Could wait for that runner's execution to complete
3. Could wait for *any* execution to occur

Option 2/3 requires inter-process signaling (e.g., waiting on a file or signal).

## Questions for Discussion

1. **Should `--wait` wait for existing runners?**
   - Yes: More intuitive ("wait for build to complete regardless of who started it")
   - No: Simpler ("wait only if I'm the runner")

2. **What exit code for "runner spawned"?**
   - `0`: Simple, "success" semantically
   - `80` (new): Distinguishes "scheduled" from "executed"
   - Keep `77`: Overload to mean "scheduled" (whether new runner or existing)

3. **Should non-blocking be the new default?**
   - Yes: Matches expectations from similar tools, more predictable
   - No: Breaking change for existing users who expect blocking

4. **Alternative: `--background` instead of default change?**
   - Add `--background` flag that backgrounds the runner
   - Keep current behavior as default
   - Less disruptive but doesn't solve the UX problem

## Migration Path

If we change the default behavior:

```
v1.x (current):   Blocking if runner, non-blocking if queued
v2.0:             Non-blocking by default, --wait for blocking
```

Could add deprecation warnings:
```
pacer: warning: Default behavior will change in v2.0. Use --wait for blocking, or set PACER_WAIT=1 to opt-in now.
```

## Example Usage After Implementation

```bash
# Fire and forget - always fast
fswatch ./src | while read; do
  pacer build 500 make  # Always returns immediately
done

# Interactive - wait for result
pacer --wait build 500 make
if [[ $? -eq 0 ]]; then
  echo "Build succeeded!"
fi

# Explicit no-wait with skip semantics (unchanged)
pacer --no-wait build 500 make  # Exit 76 if active

# Combined: wait only if I become runner, skip if busy
pacer --wait --no-wait build 500 make  # Would this make sense?
# Probably not - --no-wait should still skip immediately
```

## Conclusion

Recommend **Option A/C** with:
- Non-blocking by default (fork runner to background)
- `--wait` flag for blocking behavior
- Exit code `0` for "scheduled" (either spawned or queued)
- `--wait` returns actual command exit code

This provides consistent, predictable behavior while allowing blocking when needed.
