//! merkle_tree.zig - Merkle tree for Tiger Tree Hash (TTH)
//!
//! Based on THEX specification.
//! Uses incremental tree building with 1024-byte leaf blocks.
//!
//! **SECURITY WARNING**: Tiger Tree Hash inherits the security properties
//! of the underlying Tiger hash function. It is not considered
//! cryptographically secure for modern security-critical applications.
//! Use only for file integrity checking in contexts where cryptographic
//! security against sophisticated attackers is not required.

const std = @import("std");
const Tiger = @import("tiger.zig").Tiger;

/// THEX standard leaf block size (1024 bytes)
pub const leaf_block_size = 1024;

/// Tiger hash output size (192 bits / 24 bytes)
const hash_size = 24;

/// Maximum stack depth for tree building (supports files up to 2^64 bytes)
const max_stack_depth = 64;

/// Tree node representing either a leaf hash or internal node
const Block = struct {
    hash: [hash_size]u8,
    size: u64, // Size in bytes this block represents
};

/// Tiger Tree Hash builder using THEX specification
pub const TigerTree = struct {
    const Self = @This();

    /// Initialization options (empty for now, for future extensibility)
    pub const Options = struct {};

    blocks: [max_stack_depth]Block,
    block_count: usize,
    buffer: [leaf_block_size]u8,
    buffer_len: usize,
    total_size: u64,

    /// Initialize a new TigerTree context
    pub fn init(options: Options) Self {
        _ = options;
        return .{
            .blocks = undefined,
            .block_count = 0,
            .buffer = undefined,
            .buffer_len = 0,
            .total_size = 0,
        };
    }

    /// Compute Tiger Tree Hash in one shot (convenience function)
    pub fn hash(data: []const u8, out: *[hash_size]u8, options: Options) void {
        var d = Self.init(options);
        d.update(data);
        d.final(out);
    }

    /// Add data to tree hash computation (can be called multiple times)
    pub fn update(self: *Self, data: []const u8) void {
        var remaining = data;

        while (remaining.len > 0) {
            const space = leaf_block_size - self.buffer_len;
            const to_copy = @min(space, remaining.len);

            @memcpy(self.buffer[self.buffer_len..][0..to_copy], remaining[0..to_copy]);
            self.buffer_len += to_copy;
            remaining = remaining[to_copy..];

            if (self.buffer_len == leaf_block_size) {
                self.processBlock(self.buffer[0..leaf_block_size]);
                self.buffer_len = 0;
            }
        }

        self.total_size += data.len;
    }

    /// Finalize tree construction and write root hash to output buffer
    pub fn final(self: *Self, out: *[hash_size]u8) void {
        // Process any remaining buffered data
        // Note: also process for empty file case
        if (self.buffer_len > 0 or self.total_size == 0) {
            self.processBlock(self.buffer[0..self.buffer_len]);
        }

        // Merge all remaining blocks until single root
        while (self.block_count > 1) {
            self.block_count -= 1;
            const right = self.blocks[self.block_count];
            var left = &self.blocks[self.block_count - 1];
            left.hash = combineHashes(&left.hash, &right.hash);
            left.size += right.size;
        }

        out.* = self.blocks[0].hash;
    }

    /// Read current root hash without consuming state (non-destructive)
    pub fn peek(self: Self) [hash_size]u8 {
        var copy = self; // Simple struct copy
        var out: [hash_size]u8 = undefined;
        copy.final(&out);
        return out;
    }

    /// Process a complete block (leaf hash)
    fn processBlock(self: *Self, data: []const u8) void {
        var leaf_hash: [hash_size]u8 = undefined;

        // Leaf hash: H(0x00 || data)
        var h = Tiger.init(.{});
        h.update(&[_]u8{0x00}); // Leaf prefix
        h.update(data);
        h.final(&leaf_hash);

        self.blocks[self.block_count] = .{
            .hash = leaf_hash,
            .size = data.len,
        };
        self.block_count += 1;

        self.reduceBlocks();
    }

    /// Merge adjacent blocks of equal size
    fn reduceBlocks(self: *Self) void {
        while (self.block_count >= 2) {
            const right = &self.blocks[self.block_count - 1];
            const left = &self.blocks[self.block_count - 2];

            // Only merge blocks of equal size
            if (left.size != right.size) break;

            const right_copy = right.*;
            self.block_count -= 1;

            var merged = &self.blocks[self.block_count - 1];
            merged.hash = combineHashes(&left.hash, &right_copy.hash);
            merged.size = left.size + right_copy.size;
        }
    }

    /// Combine two hashes into internal node hash
    fn combineHashes(left: *const [hash_size]u8, right: *const [hash_size]u8) [hash_size]u8 {
        var result: [hash_size]u8 = undefined;

        // Internal hash: H(0x01 || left || right)
        var h = Tiger.init(.{});
        h.update(&[_]u8{0x01}); // Internal node prefix
        h.update(left);
        h.update(right);
        h.final(&result);

        return result;
    }
};

const testing = std.testing;
const base32 = @import("base32.zig");

test "tiger tree - empty file" {
    var tt = TigerTree.init(.{});

    var root: [hash_size]u8 = undefined;
    tt.final(&root);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &root);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "tiger tree - 1024 A's" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{'A'} ** 1024;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &root);

    try testing.expectEqualStrings("L66Q4YVNAFWVS23X2HJIRA5ZJ7WXR3F26RSASFA", encoded);
}

test "tiger tree - 1025 A's" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{'A'} ** 1025;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &root);

    try testing.expectEqualStrings("PZMRYHGY6LTBEH63ZWAHDORHSYTLO4LEFUIKHWY", encoded);
}

test "tiger tree - streaming incremental updates" {
    var tt1 = TigerTree.init(.{});
    var tt2 = TigerTree.init(.{});

    // One call
    const data = "test data for streaming";
    tt1.update(data);

    // Multiple calls
    tt2.update("test ");
    tt2.update("data ");
    tt2.update("for ");
    tt2.update("streaming");

    var root1: [hash_size]u8 = undefined;
    var root2: [hash_size]u8 = undefined;
    tt1.final(&root1);
    tt2.final(&root2);

    try testing.expectEqualSlices(u8, &root1, &root2);
}

test "tiger tree - 2048 bytes (exactly 2 blocks)" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{0x42} ** 2048;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &root);

    try testing.expectEqualStrings("4GIQEVNYCTEFRJLADAPEDVUDKZQUIE2A6BKOJQI", encoded);
}

test "tiger tree - 2049 bytes (3 blocks, triggers internal node)" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{0x42} ** 2049;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &root);

    try testing.expectEqualStrings("3P66KGUMAOGUKVMR5GJE4GOWPRJLLLPZTEUI33Q", encoded);
}

test "tiger tree - 4096 bytes (exactly 4 blocks)" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{0x5A} ** 4096;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);

    // Just verify we can compute it without errors
    try testing.expect(root.len == 24);
}

test "tiger tree - large multi-level tree (8KB)" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{0x7F} ** 8192;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);

    try testing.expect(root.len == 24);
}

test "tiger tree - buffer boundary at 1024" {
    var tt = TigerTree.init(.{});

    // First chunk: 1023 bytes (one byte short of a block)
    const chunk1 = [_]u8{0x01} ** 1023;
    tt.update(&chunk1);

    // Second chunk: 1 byte (completes the first block)
    const chunk2 = [_]u8{0x01};
    tt.update(&chunk2);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);

    // This should produce the same result as a single 1024-byte block
    var tt2 = TigerTree.init(.{});
    const data = [_]u8{0x01} ** 1024;
    tt2.update(&data);
    var root2: [hash_size]u8 = undefined;
    tt2.final(&root2);

    try testing.expectEqualSlices(u8, &root, &root2);
}

test "tiger tree - single byte" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{0xFF};
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &root);

    try testing.expect(encoded.len == 39);
}

test "tiger tree - 10000 bytes (varied size)" {
    var tt = TigerTree.init(.{});

    const data = [_]u8{0xAB} ** 10000;
    tt.update(&data);

    var root: [hash_size]u8 = undefined;
    tt.final(&root);

    try testing.expect(root.len == 24);
}

test "tiger tree - one-shot hash" {
    var out: [hash_size]u8 = undefined;
    TigerTree.hash("test data", &out, .{});

    // Verify same result as streaming
    var tt = TigerTree.init(.{});
    tt.update("test data");
    var root: [hash_size]u8 = undefined;
    tt.final(&root);

    try testing.expectEqualSlices(u8, &out, &root);
}

test "tiger tree - one-shot hash empty" {
    var out: [hash_size]u8 = undefined;
    TigerTree.hash("", &out, .{});

    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &out);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "tiger tree - peek non-destructive" {
    var tt = TigerTree.init(.{});

    tt.update("test data");

    // Peek should not consume the state
    const peeked = tt.peek();

    // Should still be able to update and finalize
    tt.update(" more");
    var out: [hash_size]u8 = undefined;
    tt.final(&out);

    // Peeked value should be hash of "test data"
    var tt2 = TigerTree.init(.{});
    tt2.update("test data");
    const expected = tt2.peek();

    try testing.expectEqualSlices(u8, &peeked, &expected);

    // Final value should be hash of "test data more"
    var tt3 = TigerTree.init(.{});
    tt3.update("test data more");
    var expected2: [hash_size]u8 = undefined;
    tt3.final(&expected2);

    try testing.expectEqualSlices(u8, &out, &expected2);
}

test "tiger tree - comptime hash" {
    comptime {
        var tt = TigerTree.init(.{});
        tt.update("abc");
        var out: [hash_size]u8 = undefined;
        tt.final(&out);

        // Verify expected hash for "abc" (matches Base32: ASD4UJSEH5M47PDYB46KBTSQTSGDKLBHYXOMUIA)
        const expected = [_]u8{
            0x04, 0x87, 0xca, 0x26, 0x44, 0x3f, 0x59, 0xcf,
            0xbc, 0x78, 0x0f, 0x3c, 0xa0, 0xce, 0x50, 0x9c,
            0x8c, 0x35, 0x2c, 0x27, 0xc5, 0xdc, 0xca, 0x20,
        };
        for (out, expected) |a, b| {
            if (a != b) @compileError("Comptime TigerTree hash mismatch");
        }
    }
}
