# Pacer Examples

This directory contains example scripts that demonstrate pacer's unique capabilities for shell-based debounce, throttle, and coordination.

## Quick Start

```bash
# Run any example
./01_basic_debounce.sh

# Or from the repo root
./examples/01_basic_debounce.sh
```

**Requirements:** Bash 4.3+, `flock` command

## Why Pacer?

Pacer solves a problem that in-process libraries (like lodash.debounce or TanStack Pacer in JavaScript) cannot: **cross-process coordination**.

When events come from file watchers, window managers, or system signals, each event is a **separate shell invocation** with no shared memory. Pacer coordinates these through filesystem-based state.

## Example Overview

### Core Concepts

| Example | Description | Key Concept |
|---------|-------------|-------------|
| [01_basic_debounce.sh](./01_basic_debounce.sh) | Wait for activity to settle | Timer resets on every call |
| [02_basic_throttle.sh](./02_basic_throttle.sh) | Rate-limit to fixed intervals | Fixed windows, steady heartbeat |
| [03_cross_process_coordination.sh](./03_cross_process_coordination.sh) | Coordinate separate processes | Filesystem-based state |
| [04_leading_trailing_edges.sh](./04_leading_trailing_edges.sh) | Control execution timing | When to run relative to burst |

### Advanced Features

| Example | Description | Key Concept |
|---------|-------------|-------------|
| [05_single_flight.sh](./05_single_flight.sh) | Prevent overlapping executions | Run lock per ID |
| [06_cross_mode_coordination.sh](./06_cross_mode_coordination.sh) | Debounce + throttle together | Smart skip detection |
| [07_timeout_handling.sh](./07_timeout_handling.sh) | Kill hung commands | Exit code 79 on timeout |
| [08_last_call_wins.sh](./08_last_call_wins.sh) | Use most recent arguments | Safe argument storage |

### Real-World Integration

| Example | Description | Key Concept |
|---------|-------------|-------------|
| [09_real_world_file_watcher.sh](./09_real_world_file_watcher.sh) | File watcher patterns | fswatch/inotify integration |
| [10_state_inspection.sh](./10_state_inspection.sh) | Debug and manage state | --status, --reset, PACER_DEBUG |

## Feature Comparison

### Debounce vs Throttle

```
                    DEBOUNCE              THROTTLE
Timer resets?       Yes, every call       No, fixed windows
During burst:       Waits indefinitely    Fires at intervals
After burst:        Fires once            Fires once (if trailing)

Example: 10 events over 500ms, delay=200ms

DEBOUNCE: Fires ONCE at 700ms (after quiet)
THROTTLE: Fires at 0ms, 200ms, 400ms, ~500ms (steady beat)
```

### Pacer vs Other Tools

| Feature | pacer | lodash.debounce | TanStack Pacer | flock |
|---------|:-----:|:---------------:|:--------------:|:-----:|
| Debounce | ✓ | ✓ | ✓ | |
| Throttle | ✓ | ✓ | ✓ | |
| Single-flight | ✓ | | ✓ | ✓ |
| **Cross-process** | **✓** | | | ✓ |
| Leading/trailing | ✓ | ✓ | ✓ | |
| Last-call-wins | ✓ | | ✓ | |
| Timeout | ✓ | | | |
| **Language** | **Shell** | JS | JS/TS | C |

## Common Patterns

### File Watching

```bash
# Rebuild when source changes
fswatch -0 ./src | xargs -0 -n1 -I{} pacer build 500 make

# Compile Sass after edits settle
fswatch ./styles/**/*.scss | while read; do
  pacer sass 300 sass src/:dist/
done
```

### System Events

```bash
# Terminal resize
trap 'pacer --debounce resize 150 redraw_ui' SIGWINCH

# Network changes
scutil --watch | while read; do
  pacer --debounce network 2000 ./update-routes.sh
done
```

### Window Managers (yabai/skhd/sketchybar)

```bash
# Coordinate multiple event types with same ID
yabai -m signal --add event=window_created \
  action="pacer --throttle ui 100 sketchybar --reload"
yabai -m signal --add event=window_title_changed \
  action="pacer --debounce ui 1000 sketchybar --reload"
```

### API Rate Limiting

```bash
# Max 1 call per second with 5s timeout
pacer --throttle --timeout 5000 api 1000 curl https://api.example.com
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Command executed successfully |
| `75` | Busy acquiring lock (transient) |
| `76` | Skipped (--no-wait mode) |
| `77` | Queued (another runner will execute) |
| `78` | Bad usage |
| `79` | Command killed (--timeout) |
| `70` | OS/IO failure |

## Debugging

```bash
# Enable debug logging
PACER_DEBUG=1 pacer build 500 make

# Log to file (for background processes)
PACER_DEBUG=1 PACER_LOG_FILE=/tmp/pacer.log pacer build 500 make

# View state
pacer --status

# Reset stuck state
pacer --reset-all myid
```

## Further Reading

- [Main README](../README.md) - Full documentation
- [TanStack Pacer](https://tanstack.com/pacer) - JavaScript inspiration
- `pacer --help` - Complete usage information
