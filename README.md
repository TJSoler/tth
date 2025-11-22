# TTH (Tiger Tree Hash) Library

A pure Zig implementation of Tiger Tree Hash (TTH), commonly used in peer-to-peer file sharing protocols like DC++.

## Features

- **Pure Zig implementation** - No external C dependencies
- **Tiger hash algorithm** - 192-bit cryptographic hash optimized for 64-bit platforms
- **Merkle tree construction** - Following the THEX specification with 1024-byte leaf blocks
- **RFC 4648 Base32 encoding** - For hash representation compatible with DC++ and other tools
- **Fully tested** - Includes comprehensive test suite with known test vectors

## Installation

Add TTH to your project using the Zig package manager. Use a specific version tag for reproducible builds:

```bash
# Fetch a specific version (recommended)
zig fetch --save https://github.com/tth/tth/archive/refs/tags/v0.1.0.tar.gz
```

This will output the correct hash. Add it to your `build.zig.zon`:

```zig
.dependencies = .{
    .tth = .{
        .url = "https://github.com/tth/tth/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "1220...", // Use the hash from zig fetch
    },
},
```

Then in your `build.zig`:

```zig
const tth = b.dependency("tth", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("tth", tth.module("tth"));
```

### Development / Latest

To use the latest development version from main branch:

```bash
zig fetch --save https://github.com/tth/tth/archive/refs/heads/main.tar.gz
```

Note: Using main branch is not recommended for production as it may contain breaking changes.

## Public API

The library exposes a clean, minimal API:

**High-level functions:**
- `tth.compute(allocator, data)` - Compute TTH from data
- `tth.computeFromFile(allocator, path)` - Compute TTH from file

**Types:**
- `tth.Tiger` - Tiger hash for incremental hashing
- `tth.TigerTree` - Tiger Tree Hash builder

**Constants:**
- `tth.digest_length` - Tiger hash output size (24 bytes)
- `tth.block_length` - Tiger hash block size (64 bytes)
- `tth.BLOCK_SIZE` - THEX leaf block size (1024 bytes)

**Base32 encoding:**
- `tth.base32.encode(allocator, data)` - Encode to Base32
- `tth.base32.decode(allocator, data)` - Decode from Base32

## Usage

### As a Library

Add the TTH module to your `build.zig`:

```zig
const tth = b.dependency("tth", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("tth", tth.module("tth"));
```

Then use it in your code:

```zig
const std = @import("std");
const tth = @import("tth");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Compute TTH from data
    const data = "Hello, World!";
    const hash = try tth.compute(allocator, data);

    // Encode to Base32
    const encoded = try tth.base32.encode(allocator, &hash);
    defer allocator.free(encoded);

    std.debug.print("TTH: {s}\n", .{encoded});
}
```

### Computing TTH from a File

```zig
const hash = try tth.computeFromFile(allocator, "path/to/file");
const encoded = try tth.base32.encode(allocator, &hash);
defer allocator.free(encoded);

std.debug.print("TTH: {s}\n", .{encoded});
```

### Lower-level API

For more control, use the `TigerTree` directly:

```zig
var tree = tth.TigerTree.init(allocator);
defer tree.deinit();

// Update with data chunks
try tree.update(chunk1);
try tree.update(chunk2);

// Get final hash
const hash = try tree.finalize();
```

### Using Tiger Hash Directly

```zig
var h = tth.Tiger.init();
h.update("some data");

var digest: [24]u8 = undefined;
h.final(&digest);
```

## Example: CLI Tool

The `examples/` folder includes a CLI tool (`tth.zig`) that demonstrates how to use the library to compute TTH hashes from files:

```bash
# Build
zig build

# Run
./zig-out/bin/tth path/to/file
```

Example output:
```
TTH (path/to/file): LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ
```

See `examples/tth.zig` for the full implementation.

## Testing

Run the test suite:

```bash
zig build test
```

For optimized performance testing:

```bash
zig build test -Doptimize=ReleaseFast
```

## Compatibility

The implementation is compatible with:
- DC++ TTH hashes
- rhash TTH output
- EiskaltDC++ implementation
- Any tool following the THEX specification

Test vectors are verified against known DC++ and rhash outputs.

## Technical Details

- **Tiger Hash**: 192-bit (24-byte) hash with 512-bit (64-byte) blocks
- **Leaf Size**: 1024 bytes per leaf block (THEX standard)
- **Tree Construction**: Incremental Merkle tree with binary reduction
- **Base32 Alphabet**: RFC 4648 (A-Z, 2-7)
- **Hash Prefixes**: 0x00 for leaves, 0x01 for internal nodes

## References

- [Tiger Hash Specification](https://www.cl.cam.ac.uk/~rja14/Papers/tiger.pdf) by Ross Anderson and Eli Biham
- [THEX - Tree Hash Exchange](http://adc.sourceforge.net/draft-jchapweske-thex-02.html)
- [RFC 4648 - Base32 Encoding](https://tools.ietf.org/html/rfc4648)
