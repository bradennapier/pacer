<p align="center">
  <h1 align="center">pacer</h1>
  <p align="center">
    <strong>Single-flight debounce/throttle for shell scripts</strong>
  </p>
  <p align="center">
    <a href="#installation">Installation</a> •
    <a href="#quick-start">Quick Start</a> •
    <a href="#examples">Examples</a> •
    <a href="#how-it-works">How It Works</a>
  </p>
</p>

---

Stop your shell commands from stampeding. **Pacer** coordinates concurrent invocations so expensive operations run exactly when needed — no sooner, no more often.

```bash
# Debounce: wait for event storm to settle, then run once
fswatch ./src | xargs -I{} pacer build 500 make

# Throttle: run immediately, then at most once per interval
pacer --throttle scroll 100 ./update-indicator.sh

# Mix both for the same target — they coordinate automatically
pacer --throttle  ui-update 100  ./refresh.sh   # window events (fast)
pacer --debounce  ui-update 1000 ./refresh.sh   # title spam (wait for quiet)
```

## Why Pacer?

Event sources like file watchers, window managers, and system signals can fire dozens of times per second. Without coordination:

| Problem | Impact |
|---------|--------|
| **Wasted CPU** | Rebuilding 50 times during a git checkout |
| **Race conditions** | Overlapping writes corrupt state |
| **Notification spam** | Alert fatigue from duplicate messages |

Pacer brings battle-tested async patterns to the shell.

> **Inspired by [TanStack Pacer](https://tanstack.com/pacer)** — the excellent async coordination library for JavaScript/TypeScript. This project borrows naming conventions and conceptual patterns from TanStack's work. If you're building JS/TS applications, check out the original.

---

## Features

| Feature | Description |
|---------|-------------|
| **Debounce** | Wait for "quiet" before running (default) |
| **Throttle** | Run at most once per interval |
| **Single-flight** | Command never overlaps itself for the same ID |
| **Cross-mode** | Throttle and debounce with same ID coordinate |
| **Edge control** | Leading/trailing execution timing |
| **Last-call-wins** | Always runs with the most recent arguments |
| **Timeout** | Kill commands that run too long |
| **Zero deps** | Pure bash (+ flock on macOS) |

---

## Installation

### Homebrew (macOS/Linux)

```bash
brew install pacer
```

### Manual

```bash
# macOS needs flock
brew install flock

# Install pacer
curl -fsSL https://raw.githubusercontent.com/bradennapier/pacer/main/pacer \
  -o /usr/local/bin/pacer
chmod +x /usr/local/bin/pacer
```

**Requirements:** Bash 4.3+, flock

---

## Quick Start

```bash
pacer [MODE] [OPTIONS] <id> <delay_ms> <command> [args...]
```

| Argument | Description |
|----------|-------------|
| `id` | Unique identifier for this operation (e.g., `build`, `notify`) |
| `delay_ms` | Debounce quiet period or throttle interval in milliseconds |
| `command` | The command to execute |
| `args` | Arguments passed to command (supports spaces, quotes, etc.) |

### Modes & Options

```
Modes:
  --debounce            Wait for quiet, then run (DEFAULT)
  --throttle            Run immediately, rate-limit subsequent

Options:
  --leading  true|false   Run at START of burst (default: debounce=false, throttle=true)
  --trailing true|false   Run at END of burst (default: true)
  --timeout <ms>          Kill command if it runs longer than <ms> (exit code 79)
  --no-wait               Exit immediately if busy, don't update state

Operations:
  --status [mode id]     Show state for all keys, or specific (mode, id)
  --reset <mode> <id>    Kill runner and clear state
  --reset-all <id>       Reset both debounce and throttle for <id>
```

---

## Choosing a Mode

> **See also:** TanStack's [Which Utility Should I Choose?](https://tanstack.com/pacer/latest/docs/guides/which-pacer-utility-should-i-choose) guide

### The Key Difference

|                    | Debounce | Throttle |
|--------------------|----------|----------|
| Timer resets?      | Yes, on every call | No, fixed windows |
| During burst       | Waits indefinitely | Fires at intervals |
| After burst        | Fires once | Fires once (if trailing) |

**Rule of thumb:**
- "Wait for idle" → **Debounce**
- "Steady heartbeat" → **Throttle**

**Example:** 10 rapid events over 500ms, delay=200ms using default leading/trailing flags

- **Debounce:** Timer keeps resetting → fires **once** at 700ms (after quiet)
- **Throttle:** Fixed 200ms windows → fires at **0ms, 200ms, 400ms, ~500ms**

---

### What Mode Should I Use?

<details>
<summary><strong>When to Use Debounce</strong> — wait for "quiet"</summary>

<br>

Debounce waits for "quiet" — the timer **resets on every call**. Use when you only care about the **final state** after activity stops.

| Flags | Pattern | Use Cases |
|-------|---------|-----------|
| `--leading false --trailing true` *(default)* | Wait for silence, then act | Search input, auto-save, config reload |
| `--leading true --trailing true` | Act now, then again after silence | Form validation, live preview |
| `--leading true --trailing false` | Act once, ignore until cooldown | Button clicks, notifications |

```bash
# Search after user stops typing (300ms)
pacer search 300 ./query.sh "$input"

# Prevent double-submit on button click
pacer --leading true --trailing false submit 1000 ./handle-click.sh
```

**Timeline:** Timer resets on each call → collapses burst into 1-2 executions.
```
Events:  x  x  x  x  x
         |--|--|--|--|----->
         [timer resets]    ^ runs once (after quiet)
```

</details>

---

<details>
<summary><strong>When to Use Throttle</strong> — periodic updates</summary>

<br>

Throttle guarantees max frequency — **fixed windows, timer never resets**. Use when you want **periodic updates** during continuous activity.

| Flags | Pattern | Use Cases |
|-------|---------|-----------|
| `--leading true --trailing true` *(default)* | Act now, periodically, then final | Scroll/drag UI, live metrics |
| `--leading true --trailing false` | Act now, then at fixed intervals | Progress polling, rate limiting |
| `--leading false --trailing true` | Wait for interval, capture final | Batch processing, aggregation |

```bash
# Scroll indicator: instant + steady updates + final position
pacer --throttle scroll 100 ./update.sh

# Rate-limit API: enforce max 1 call/second
pacer --throttle --leading true --trailing false api 1000 curl https://api.example.com
```

**Timeline:** Fixed windows → spreads burst across multiple executions.
```
Events:  x  x  x  x  x
         v--|--|--|--|----->v
         ^ runs            ^ runs again
         [fixed window]
```

</details>

---

<details>
<summary><strong>Leading & Trailing Edge Control</strong></summary>

<br>

Control exactly when your command fires:

| Combination | Behavior |
|-------------|----------|
| `--leading false --trailing true` | Wait for quiet, then run once *(debounce default)* |
| `--leading true --trailing true` | Run immediately AND after quiet *(throttle default)* |
| `--leading true --trailing false` | Run once immediately, ignore burst |
| `--leading false --trailing false` | Never runs *(don't use this)* |

```bash
# Instant feedback on click, ignore rapid clicks for 1s
pacer --debounce --leading true --trailing false click 1000 ./handle.sh

# Update on first scroll AND after scrolling stops
pacer --throttle --leading true --trailing true scroll 200 ./update.sh
```

</details>

---

## Cross-Mode Coordination

When throttle and debounce share an ID, they **coordinate automatically**:

```bash
# Window events: fast throttle (100ms)
yabai -m signal --add event=window_created \
  action="pacer --throttle ui 100 ./refresh.sh"

# Title changes: slow debounce (1s) — these can spam hundreds of events
yabai -m signal --add event=window_title_changed \
  action="pacer --debounce ui 1000 ./refresh.sh"
```

**What happens:**
1. Throttle runs immediately on window create
2. Title spam starts debounce countdown (1s)
3. If throttle runs during that 1s, debounce detects it and skips
4. No duplicate executions, no wasted work


## Examples

<details>
<summary><strong>File Watching</strong></summary>

```bash
# Rebuild on source changes (wait for git checkout to finish)
fswatch -0 ./src | xargs -0 -n1 -I{} pacer build 500 make

# Compile Sass after edits settle
fswatch ./styles/**/*.scss | while read; do
  pacer sass 300 sass src/:dist/
done
```

</details>

<details>
<summary><strong>System Events</strong></summary>

```bash
# Handle terminal resize after it settles
trap 'pacer --debounce resize 150 redraw_ui' SIGWINCH

# React to network changes (wait for flapping to stop)
scutil --watch | while read; do
  pacer --debounce network 2000 ./update-routes.sh
done
```

</details>

<details>
<summary><strong>Notifications & Alerts</strong></summary>

```bash
# Alert on log errors, max once per 30s
tail -F /var/log/app.log | grep --line-buffered ERROR | while read line; do
  pacer --throttle alert 30000 notify-send "Error" "$line"
done
```

</details>

<details>
<summary><strong>Docker & Containers</strong></summary>

```bash
# Regenerate nginx config when containers change
docker events --filter event=start --filter event=stop | while read; do
  pacer --debounce nginx 2000 ./regen-upstream.sh
done
```

</details>

<details>
<summary><strong>Window Managers (yabai, skhd, sketchybar)</strong></summary>

```bash
# sketchybar refresh — coordinate multiple event types
yabai -m signal --add event=window_created \
  action="pacer --throttle sketchybar_reload 100 sketchybar --reload"
yabai -m signal --add event=window_destroyed \
  action="pacer --throttle sketchybar_reload 100 sketchybar --reload"
yabai -m signal --add event=window_title_changed \
  action="pacer --debounce sketchybar_reload 1000 sketchybar --reload"
```

</details>

<details>
<summary><strong>Timeouts</strong></summary>

```bash
# Kill build if it takes longer than 30 seconds
pacer --timeout 30000 build 500 make

# API calls with timeout — prevent hung requests blocking the queue
pacer --throttle --timeout 5000 api 1000 curl https://api.example.com/data

# Git operations with timeout — don't let network issues hang forever
pacer --timeout 10000 git-sync 5000 git fetch --all
```

</details>

---

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Command executed (returns command's exit code) |
| `75` | Busy acquiring lock (transient contention) |
| `76` | Skipped — active runner (`--no-wait` mode) |
| `77` | Queued — another runner scheduled, state updated |
| `78` | Bad usage |
| `79` | Command killed due to `--timeout` |
| `70` | OS/IO failure |

---

## How It Works

Pacer uses filesystem-based coordination in `/tmp/pacer/`:

| Component | Purpose |
|-----------|---------|
| **State lock** | Serializes decision-making per (mode, id) |
| **Run lock** | Prevents overlapping execution per id (shared across modes) |
| **Last-exec timestamp** | Enables cross-mode "already satisfied" detection |
| **Command file** | Stores latest arguments (NUL-delimited for safety) |
| **Runner stamp** | PID + start time + lstart for safe process identification |

The **smart skip** feature checks if another mode already executed since a pending timer was set. If so, the pending execution is skipped as redundant.

---

## Comparison

| Feature | pacer | [TanStack Pacer](https://tanstack.com/pacer) | timeout | flock |
|---------|:-----:|:--------------------------------------------:|:-------:|:-----:|
| Debounce | ✓ | ✓ | | |
| Throttle | ✓ | ✓ | | |
| Rate limiting | | ✓ | | |
| Queueing | | ✓ | | |
| Batching | | ✓ | | |
| Single-flight | ✓ | ✓ | | ✓ |
| Leading/trailing edge | ✓ | ✓ | | |
| Cross-process coordination | ✓ | | | ✓ |
| Last-call-wins args | ✓ | ✓ | | |
| Timeout | ✓ | | ✓ | |
| **Language** | Bash | JS/TS | C | C |

**When to use which:**
- **pacer** — Shell scripts, CLI tools, system events, file watchers
- **TanStack Pacer** — JavaScript/TypeScript applications, API calls, UI events
- **timeout** — Kill long-running commands after a duration
- **flock** — Simple mutex locking without timing coordination

---

## Acknowledgments

This project is inspired by and named after [TanStack Pacer](https://tanstack.com/pacer) by Tanner Linsley. The API design, terminology (debounce, throttle, leading/trailing edge), and conceptual approach are adapted from TanStack's excellent work for the JavaScript ecosystem.

**Key differences from TanStack Pacer:**
- **Shell-native** — Works with any command, no runtime required
- **Cross-process** — Coordinates separate invocations via filesystem locks
- **No rate limiting** — TanStack supports token bucket rate limiting; this doesn't (yet)
- **No queueing/batching** — TanStack can queue and batch calls; this uses last-call-wins

---

## License

[MIT License](LICENSE)

## Contributing

Issues and PRs welcome at [github.com/bradennapier/pacer](https://github.com/bradennapier/pacer)
