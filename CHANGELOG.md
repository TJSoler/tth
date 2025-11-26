# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- CI workflow for pull requests with multi-architecture testing (x86_64, aarch64)
- Dependabot configuration for GitHub Actions dependencies
- Concurrency control for CI workflow to cancel outdated builds
- Performance regression check job in CI (interleaved benchmarking on PRs with 10% threshold)
- MIT License file
- Comprehensive benchmark suite (`benchmark.zig`) for Tiger, TigerTree, and Base32 operations
- Benchmark comparison script (`scripts/compare_benchmarks.zig`) for CI performance analysis
- `tth.version` constant for library version information
- `Tiger.hash()` - one-shot hash computation function
- `Tiger.peek()` - non-destructive hash read (copies state before finalizing)
- `Tiger.Options` struct for future API extensibility
- `TigerTree.hash()` - one-shot TTH computation function
- `TigerTree.peek()` - non-destructive hash read
- `TigerTree.Options` struct for future API extensibility
- Security warnings in module documentation for Tiger and TigerTree
- RFC 4648 test vectors for Base32 implementation
- Additional test coverage across all modules (10+ new tests)
- Comptime test for TigerTree (hash computation at compile time)

### Changed

- **BREAKING**: Renamed `BLOCK_SIZE` to `leaf_block_size` (snake_case consistency with Zig stdlib)
- **BREAKING**: Renamed `TigerTree.finalize()` to `TigerTree.final()` (consistency with Zig crypto stdlib)
- **BREAKING**: `Tiger.init()` now requires `Options` parameter (use `.{}` for defaults)
- **BREAKING**: `TigerTree.init()` no longer requires an allocator parameter (zero heap allocation)
- **BREAKING**: `TigerTree.hash()` no longer requires an allocator parameter
- **BREAKING**: `TigerTree.final()` now takes output parameter instead of returning value
- **BREAKING**: `TigerTree` methods are now infallible (no allocation errors)
- **BREAKING**: `TigerTree.peek()` now returns `[24]u8` instead of `![24]u8`
- Made `tiger` and `merkle` modules private to reduce API surface area (public types `tth.Tiger` and `tth.TigerTree` remain available)
- `TigerTree` now uses fixed-size internal stack (~3KB) instead of dynamic allocation
- Improved buffer handling in `Tiger.update()` for better performance
- GitHub repository URLs in README examples (corrected from `tth/tth` to `tjsoler/tth`)

### Removed

- **BREAKING**: `TigerTree.deinit()` - no longer needed (no heap allocation)
- **BREAKING**: `compute()` - use `TigerTree.hash()` directly
- **BREAKING**: `computeFromFile()` - users handle file I/O directly

## [0.1.0] - 2025-11-21

### Added

- Pure Zig implementation of Tiger hash algorithm (192-bit, 64-byte blocks)
- Tiger Tree Hash (TTH) implementation following THEX specification
- Merkle tree construction with 1024-byte leaf blocks
- RFC 4648 Base32 encoding/decoding for hash representation
- High-level API functions: `compute()` and `computeFromFile()`
- Incremental hashing support via `update()` pattern
- Compile-time hash computation support
- CLI tool for computing TTH hashes from files
- Comprehensive test suite with 61+ tests
- Test vectors verified against rhash implementation
- MIT license
- Complete documentation and examples

[unreleased]: https://github.com/tjsoler/tth/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tjsoler/tth/releases/tag/v0.1.0
