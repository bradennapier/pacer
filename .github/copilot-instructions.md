# Copilot Instructions for Pacer

## Project Overview

Pacer is a **single-flight debounce/throttle coordination tool for shell scripts**. It brings async patterns (debounce, throttle, leading/trailing edge) to the shell, enabling sophisticated coordination of noisy event sources like file watchers, window managers (yabai, skhd, sketchybar), and system events.

**Core Purpose**: Prevent command stampeding and overlapping executions by coordinating concurrent invocations across processes using filesystem-based locks.

**Inspiration**: Named after and inspired by [TanStack Pacer](https://tanstack.com/pacer) by Tanner Linsley. This shell implementation adapts TanStack's API design, terminology, and conceptual approach for cross-process CLI use cases.

## Technology Stack

- **Language**: Bash shell script (requires Bash 4.3+)
- **Dependencies**: `flock` (for file-based locking)
- **Testing**: `bats-core` (Bash Automated Testing System)
- **Target Platforms**: macOS and Linux

## Project Structure

```
pacer/
├── pacer                  # Main executable shell script (~35KB)
├── test/
│   └── pacer.bats        # Test suite (bats tests)
├── Formula/              # Homebrew formula
├── assets/               # Logo and images
├── Makefile             # Build/test/install commands
├── README.md            # Comprehensive documentation
└── .github/             # GitHub configuration
```

## Build, Test, and Lint Commands

### Testing
```bash
# Run full test suite (requires bats-core)
make test

# Install bats-core if needed
brew install bats-core

# Run tests directly
bats test/pacer.bats
```

### Linting
```bash
# Check bash syntax
make lint

# This runs: bash -n pacer
```

### Installation
```bash
# Install to /usr/local/bin
make install

# Install to custom location
make PREFIX=/custom/path install

# Uninstall
make uninstall
```

## Code Architecture

### Single Executable Design
The entire implementation is in a single `pacer` Bash script file. This is intentional for ease of distribution and installation.

### State Management
Pacer uses filesystem-based coordination in `/tmp/pacer/`:

- **State lock**: Serializes decision-making per (mode, id)
- **Run lock**: Prevents overlapping execution per id (shared across modes)
- **Last-exec timestamp**: Enables cross-mode "already satisfied" detection
- **Command file**: Stores latest arguments (NUL-delimited for safety)
- **Runner stamp**: PID + start time + lstart for safe process identification

### Key Concepts

1. **Single-flight execution**: A command NEVER overlaps itself for the same `<id>`
2. **Cross-mode coordination**: Throttle and debounce with the same `<id>` share execution lock
3. **Smart skip**: If one mode executes, the other mode's pending execution may be skipped as redundant
4. **Last-call-wins**: Each mode tracks its own command; runner executes the latest arguments
5. **Debounce vs Throttle**:
   - **Debounce**: Timer resets on every call; waits for "quiet" period
   - **Throttle**: Fixed windows; timer never resets; guarantees max frequency

## Coding Conventions and Best Practices

### Shell Script Style
- Use `set -euo pipefail` for safety
- Prefer `[[` over `[` for conditionals
- Quote all variable expansions unless intentional word splitting is needed
- Use `local` for function variables
- Use meaningful function names with underscores (e.g., `_log`, `_acquire_lock`)

### Error Handling
Pacer uses specific exit codes:
- `0`: Success (returns command's exit code)
- `75`: Busy acquiring lock
- `76`: Skipped (active runner with `--no-wait`)
- `77`: Queued (state updated, another runner scheduled)
- `78`: Bad usage/invalid arguments
- `79`: Command killed due to timeout
- `70`: OS/IO failure

### Testing Requirements
- All new features MUST have corresponding bats tests
- Tests should be self-contained and clean up after themselves
- Use the existing test setup/teardown pattern (creates `/tmp/pacer-test-$$`)
- Tests should verify both success cases and error conditions
- Test argument preservation, especially with spaces and special characters

### Debugging Support
The script supports debug logging via environment variables:
- `PACER_DEBUG=1`: Enable debug logging to stderr
- `PACER_LOG_FILE=/path/to/file`: Write logs to file

Always preserve and enhance debug logging for new features.

## Common Development Tasks

### Adding a New Feature
1. Update the main `pacer` script with the new functionality
2. Add corresponding test cases in `test/pacer.bats`
3. Run `make lint` to check syntax
4. Run `make test` to verify all tests pass
5. Update `README.md` with documentation and examples
6. Consider adding debug logging for troubleshooting

### Fixing a Bug
1. Write a failing test that reproduces the bug
2. Fix the bug in the `pacer` script
3. Verify the test now passes
4. Run full test suite to ensure no regressions
5. Update documentation if behavior changed

### Performance Considerations
- Minimize filesystem operations (they're slow)
- Use `flock` efficiently (it's the synchronization primitive)
- Avoid spawning unnecessary subshells
- Keep state files small and simple
- Test with rapid concurrent invocations

## Documentation Standards

- Keep `README.md` comprehensive but scannable
- Use collapsible sections (`<details>`) for examples
- Include concrete, copy-pasteable examples
- Document all flags, modes, and exit codes
- Maintain comparison table with similar tools

## Security and Safety

- Never introduce command injection vulnerabilities
- Use NUL-delimited storage for arguments (supports arbitrary characters)
- Validate all input arguments
- Handle edge cases like missing files, permission errors
- Clean up stale locks and processes safely

## Compatibility Requirements

- **Bash 4.3+** is required (uses nameref with `local -n`)
- Must work on both macOS and Linux
- macOS requires external `flock` (via Homebrew)
- Preserve POSIX compatibility where possible, but Bash-specific features are acceptable
- Test on both platforms if making system-specific changes

## Release and Distribution

- Distributed as single executable script (easy `curl` install)
- Homebrew formula in `Formula/` directory
- No build step required (pure shell script)
- Version changes require updating both script header and Homebrew formula

## Interaction with GitHub Copilot

When working on this repository:
1. Always run tests after making changes
2. Maintain the single-file architecture (don't split into multiple scripts)
3. Preserve backward compatibility unless explicitly breaking
4. Add examples to README for new features
5. Keep the code readable and well-commented (but not over-commented)
6. Follow the established patterns for mode handling (debounce/throttle)
7. Test concurrent execution scenarios thoroughly
8. Consider cross-platform implications (macOS vs Linux)

## Important Notes

- This is a production tool used in real workflows (file watching, window management)
- Changes should be conservative and well-tested
- Performance matters: this runs frequently in event-driven contexts
- The single-file design is intentional for distribution - maintain it
- Filesystem-based coordination is the core architecture - don't change lightly
