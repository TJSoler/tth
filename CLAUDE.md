# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the CLI executable
zig build

# Run the CLI tool
zig build run -- path/to/file
./zig-out/bin/tth path/to/file

# Run all tests
zig build test

# Run tests for a specific module
zig test src/tiger.zig
zig test src/merkle_tree.zig
zig test src/base32.zig

# Build with optimization
zig build -Doptimize=ReleaseFast    # Speed
zig build -Doptimize=ReleaseSmall   # Size
zig build -Doptimize=Debug          # Default

# Run benchmarks
zig build bench -Doptimize=ReleaseFast
zig build bench -Doptimize=ReleaseFast -- --filter tiger
zig build bench -Doptimize=ReleaseFast -- --json
```

## Architecture Overview

This is a pure Zig implementation of Tiger Tree Hash (TTH) with zero external dependencies. The project provides both a library module and a CLI executable.

### Module Structure (4 layers)

```
root.zig (Public API)
    ├── merkle_tree.zig (THEX Merkle tree, 1024-byte blocks)
    │   └── tiger.zig (Tiger hash: 192-bit, 64-byte blocks, 3-pass)
    └── base32.zig (RFC 4648 encoding: 24 bytes → 39 chars)
```

**Key architectural pattern**: Data flows from `root.zig` through `TigerTree` (which chunks into 1024-byte blocks) down to `Tiger` hash for each block, then results are Base32-encoded.

### Entry Points

- **Library users**: Import `src/root.zig` which exports:
  - `Tiger` - Tiger hash context (incremental hashing)
  - `TigerTree` - Merkle tree builder (incremental processing)
  - `base32` - Encoding/decoding module
  - Constants: `digest_length` (24), `block_length` (64), `leaf_block_size` (1024)

- **CLI users**: `examples/tth.zig` executable

### Build System

The build.zig creates:
1. **Module** `tth` - Library for use by other projects (root: `src/root.zig`)
2. **Executable** `tth` - CLI tool (root: `examples/tth.zig`)
3. **Benchmark** `bench` - Performance measurement (root: `src/benchmark.zig`)

### Resource Management

Both `Tiger` and `TigerTree` use fixed-size internal buffers with no heap allocation.
No cleanup is required - simply let the struct go out of scope.

### Incremental Processing

Both `Tiger` and `TigerTree` support streaming data via the `update()` pattern:
```zig
var tree = TigerTree.init(.{});
tree.update(chunk1);
tree.update(chunk2);
var hash: [24]u8 = undefined;
tree.final(&hash);
```

### THEX Specification Details

The Merkle tree implementation follows the THEX (Tree Hash EXchange) specification:
- Leaf blocks: exactly 1024 bytes (except final block)
- Leaf hash: `Tiger(0x00 || block_data)`
- Internal node hash: `Tiger(0x01 || left_hash || right_hash)`
- Tree reduction: logarithmic growth, dynamic structure

### Implementation Notes

- **Tiger hash**: 3-pass compression with 4 S-boxes (t1-t4), feed-forward mechanism
- **Base32**: RFC 4648 alphabet (A-Z, 2-7), no padding for 24-byte inputs
- **Security**: Tiger hash is NOT cryptographically secure. Use only for file integrity checking.
- **Error handling**: Both `Tiger` and `TigerTree` are infallible (no heap allocation)
- **Comptime support**: Both `Tiger` and `TigerTree` work at compile time

### Test Coverage

61+ tests across all modules with known test vectors verified against rhash outputs. Tests use only standard library - no external testing frameworks.

## Zig Standard Library Conventions

This library follows Zig standard library patterns, particularly `std/crypto` conventions. When modifying code, maintain consistency with these patterns.

### Documentation Style

**Module comments** (`//!`) at file top should include:
- Brief description of what the module provides
- Standard/specification references with URLs
- Security warnings or usage context
- Example from stdlib SHA2: includes NIST spec URLs and collision attack warnings

**Doc comments** (`///`) for public items:
- Add brief descriptions to public constants, types, and functions
- Focus on purpose, not implementation details
- Example: `/// SHA-256 truncated to leftmost 192 bits.`

**Inline comments**:
- Use sparingly for non-obvious algorithm steps
- Buffer management logic
- Bit manipulation explanations

### Naming Conventions

The Zig standard library uses **snake_case for ALL constants** without exception. This applies universally across all modules.

**Constant naming rules**:
- **Always use snake_case** (lowercase with underscores)
- **Never use UPPERCASE** (no DIGEST_LENGTH, BLOCK_SIZE, PI, etc.)
- **No variation by scope**: Both `pub const` and private `const` use snake_case
- **No variation by type**: comptime_int, arrays, floats, strings all use snake_case
- **Prefer descriptive names**: `digest_length` over `N` or `len`

**Examples from `std/crypto`**:
```zig
// ✅ Correct stdlib style
pub const digest_length = 24;
pub const block_length = 64;
pub const key_length = 32;
const iv256 = Iv32{ ... };
const sigma = [10][16]u8{ ... };

// ❌ NOT stdlib style
pub const DIGEST_LENGTH = 24;
pub const DigestLength = 24;
pub const digestLength = 24;
const IV256 = Iv32{ ... };
const SIGMA = [10][16]u8{ ... };
```

**Examples from `std/math`**:
```zig
pub const pi = 3.14159265358979323846...;
pub const e = 2.71828182845904523536...;
pub const tau = 2 * pi;
pub const ln2 = 0.69314718055994530941...;
pub const sqrt2 = 1.41421356237309504880...;
```

**Type annotations**:
- Optional but acceptable: `pub const block_length: usize = 64`
- Inferred also acceptable: `pub const block_length = 64`
- Both styles used in stdlib

**Doc comments for constants**:
```zig
/// Tiger hash output size (192 bits / 24 bytes)
pub const digest_length = 24;

/// THEX standard leaf block size
pub const block_size = 1024;
```

### Public API Conventions (Crypto Modules)

Standard hash function public API from `std/crypto`:

```zig
pub const block_length: comptime_int    // Block size in bytes
pub const digest_length: comptime_int   // Output size in bytes
pub const Options = struct {};          // Even if empty (future extensibility)

pub fn init(options: Options) Self
pub fn hash(b: []const u8, out: *[digest_length]u8, options: Options) void
pub fn update(d: *Self, b: []const u8) void
pub fn final(d: *Self, out: *[digest_length]u8) void
pub fn peek(d: Self) [digest_length]u8  // Non-destructive (copies state)
```

**Key points**:
- Add `Options` parameter even if empty (allows future extension without API breakage)
- Constants should have doc comments explaining what they represent
- `peek()` must be non-destructive (copy state before finalizing)
- Consistent naming: use `b` for byte slices, `d` for digest state, `out` for output

### Testing Patterns

**Test naming convention**: `"module_name functionality"` pattern
- `test "tiger single"` - One-shot hashing
- `test "tiger streaming"` - Multiple `update()` calls
- `test "tiger aligned final"` - Exactly block-sized input
- `test "comptime tiger"` - Compile-time execution

**Required test types** for hash functions:
1. **Basic vectors**: Empty input, simple strings ("abc"), known vectors
2. **Streaming**: Verify `update(a); update(b)` equals `update(a++b)`
3. **Aligned final**: Process exactly one or more complete blocks
4. **Comptime**: Hash must work at compile time (critical for Zig)

**No test helpers**: Use `std.testing` functions directly
- `testing.expectEqual()` for exact matches
- `testing.expectEqualSlices()` for byte arrays
- No custom assertion wrappers

**Comptime test example** (essential pattern):
```zig
test "comptime tiger" {
    comptime {
        var h = Tiger.init(.{});
        h.update("abc");
        var out: [digest_length]u8 = undefined;
        h.final(&out);
        if (out[0] != expected) @compileError("Failed");
    }
}
```

### File Organization

Standard order (from `std/crypto` modules):
1. Module doc comment (`//!`)
2. Imports (stdlib first, minimal set)
3. Public constants (with doc comments)
4. Public type definitions
5. Private constants and tables
6. Implementation functions
7. Tests at bottom

## Changelog Management

This project follows [Keep a Changelog](https://keepachangelog.com/) principles for maintaining CHANGELOG.md.

### Core Principles

- **Human-focused**: Changelogs are written for humans, not machines
- **Reverse chronological**: Latest version appears first
- **Unreleased section**: Track upcoming changes at the top of the file
- **Version dating**: Include release date in ISO 8601 format (YYYY-MM-DD)
- **Semantic Versioning**: Indicate that the project follows [SemVer](https://semver.org/)

### Change Categories

All changes must be categorized using these standard types:

- **Added**: New features
- **Changed**: Modifications to existing functionality
- **Deprecated**: Features scheduled for removal in future versions
- **Removed**: Features that have been deleted
- **Fixed**: Bug corrections
- **Security**: Vulnerability patches

### Workflow

1. **During development**: Add changes to the `[Unreleased]` section under appropriate categories
2. **At release time**:
   - Move `[Unreleased]` changes to a new version section
   - Add release date in YYYY-MM-DD format
   - Create empty `[Unreleased]` section for next cycle
   - Update version comparison links at bottom of file

### Important Rules

- Never use raw commit logs as changelog entries
- Always document breaking changes explicitly
- Document all deprecations before removing features
- Mark yanked/retracted releases with `[YANKED]` tag
- Keep entries concise and focused on impact to users
- Link to issues/PRs for additional context when relevant

### Entry Style

Write changelog entries from the user's perspective:

```markdown
### Added
- CLI tool for computing TTH hashes from files

### Changed
- Made internal modules private to reduce API surface (breaking change)

### Fixed
- Incorrect hash calculation for files larger than 1MB
```

Focus on *what changed* and *why it matters*, not implementation details.
