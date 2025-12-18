# Understanding Pacer's Blocking Behavior

Pacer's blocking behavior can be confusing because it varies depending on whether your invocation becomes the "runner" or not. This document explains when pacer blocks, when it doesn't, and how to handle each case.

## TL;DR

| Scenario | Blocks? | Exit Code | What Happens |
|----------|---------|-----------|--------------|
| Another runner exists | No | 77 | Updates command, returns immediately |
| You become runner (debounce) | Yes | 0 | Sleeps for delay, then runs command |
| You become runner (throttle, leading=true) | Yes | 0 | Runs command immediately |
| `--no-wait` when active | No | 76 | Returns immediately, no state update |

**The key insight:** You don't know in advance whether your call will block or not — it depends on whether a runner already exists.

## The Problem

When you run pacer from a shell, the behavior is unpredictable:

```bash
# First call - becomes runner, blocks for 500ms+ while waiting for quiet period
pacer build 500 make

# Second call (while first is waiting) - returns immediately with exit 77
pacer build 500 make

# After first completes, this becomes the new runner and blocks again
pacer build 500 make
```

This inconsistency creates confusion:
- In file watchers, you might expect every call to return quickly
- In interactive shells, you might expect to wait for your build to complete
- Neither expectation is reliably met

## Current Behavior Explained

### When Pacer Blocks

1. **Debounce mode (default):** The runner blocks while sleeping through the delay period, then blocks again while executing the command.

2. **Throttle mode with leading=true (default):** The first call blocks while executing the command immediately.

3. **Any mode executing a command:** The runner blocks during actual command execution.

```
Timeline (debounce, 500ms delay):

User calls:     pacer build 500 make
                 |
                 v
           +------------------+
           | Become runner    | ← Returns immediately to shell? NO!
           | Sleep 500ms      | ← BLOCKING
           | Execute 'make'   | ← BLOCKING
           +------------------+
                 |
                 v
           Returns exit code 0
```

### When Pacer Doesn't Block

1. **Another runner already exists:** Your call updates the stored command and returns exit code 77 immediately.

2. **Using `--no-wait` when active:** Returns exit code 76 immediately without updating any state.

```
Timeline (second caller):

Runner exists:  [sleeping...]

User calls:     pacer build 500 make
                 |
                 v
           +------------------+
           | Runner exists!   |
           | Update command   |
           | Exit code 77     | ← Returns IMMEDIATELY
           +------------------+
```

## Do You Need `&` (Background)?

**Short answer:** Usually no, but it depends on your use case.

### File Watchers / Event Handlers

For event-driven patterns, pacer works well because **most calls exit 77**:

```bash
# Works fine - most calls return immediately (exit 77)
fswatch ./src | while read; do
  pacer build 500 make
done
```

But the **first** call in a burst blocks, which could delay event processing slightly. If this matters:

```bash
# Guaranteed non-blocking - always backgrounds the call
fswatch ./src | while read; do
  pacer build 500 make &
done
```

### Interactive Shell

When running manually, you probably **want** to wait:

```bash
# You want to see the build output!
pacer build 500 make

# But if a build is already pending, this returns immediately (exit 77)
# and you don't see any output - potentially confusing
```

### Daemon/Signal Handlers

For system integrations (yabai, skhd, launchd), the inconsistency rarely matters:

```bash
# yabai signal handler - non-blocking is expected
yabai -m signal --add event=window_created \
  action="pacer --throttle ui 100 ./refresh.sh"
```

## Exit Codes Quick Reference

| Code | Meaning | Caller Blocked? |
|------|---------|-----------------|
| 0 | Command executed successfully | Yes (while executing) |
| 75 | Lock contention (transient) | No (50ms max) |
| 76 | Skipped (`--no-wait` mode) | No |
| 77 | Queued (runner exists) | No |
| 78 | Bad usage | No |
| 79 | Command killed (timeout) | Yes (until timeout) |

## Patterns for Handling This

### Pattern 1: Always Background

```bash
# Guaranteed non-blocking, but you lose exit codes
pacer build 500 make &
```

### Pattern 2: Check Exit Code

```bash
pacer build 500 make
case $? in
  0)  echo "Build completed" ;;
  77) echo "Build queued (runner already active)" ;;
  79) echo "Build timed out" ;;
  *)  echo "Error: $?" ;;
esac
```

### Pattern 3: Use `--no-wait` for Fire-and-Forget

```bash
# Only runs if not already active, otherwise silently skips
pacer --no-wait build 500 make
```

### Pattern 4: Wrapper Script

```bash
#!/bin/bash
# pacer-bg: always-non-blocking pacer wrapper
pacer "$@" &
pid=$!
# Optionally: track pid for later status checks
echo $pid > /tmp/pacer-bg.pid
```

## Proposed Enhancement: `--wait` Flag

To make the behavior more predictable, a future version may implement:

```bash
# Default: always non-blocking (runner auto-backgrounds)
pacer build 500 make          # Returns immediately, always

# Explicit wait: block until execution completes
pacer --wait build 500 make   # Blocks until command runs
```

This would:
1. **Auto-background the runner process** so the caller always returns immediately
2. **`--wait` flag** makes the caller block until execution completes (if it becomes runner) or the active runner finishes

See GitHub issue for discussion on this enhancement.

---

## Summary

Pacer's blocking behavior is **situational** — it depends on whether your call becomes the runner:

- **First caller (or after previous runner exits):** Blocks during delay + execution
- **Subsequent callers:** Returns immediately with exit 77

For most use cases (file watchers, signal handlers), this works fine because the fast-path (exit 77) is the common case. For interactive use, consider using `&` or a wrapper script if the unpredictable blocking is problematic.
