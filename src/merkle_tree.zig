//! merkle_tree.zig - Merkle tree for Tiger Tree Hash (TTH)
//!
//! Based on THEX specification and EiskaltDC++ implementation.
//! Uses incremental tree building with 1024-byte leaf blocks.
//!
//! **SECURITY WARNING**: Tiger Tree Hash inherits the security properties of
//! the underlying Tiger hash function. It is not considered cryptographically
//! secure for modern security-critical applications. Use only for file integrity
//! checking in peer-to-peer contexts where cryptographic security against
//! sophisticated attackers is not required.
//!
//! **MEMORY MANAGEMENT**: TigerTree requires dynamic memory allocation for the
//! tree structure. You must call `deinit()` when done to avoid memory leaks.
//! The tree grows logarithmically with file size, allocating approximately
//! O(log N) nodes for N blocks of data.

const std = @import("std");
const Tiger = @import("tiger.zig").Tiger;

/// THEX standard leaf block size (1024 bytes)
pub const leaf_block_size = 1024;

/// Tiger hash output size (192 bits / 24 bytes)
const HASH_SIZE = 24;

/// Tree node representing either a leaf hash or internal node
const Block = struct {
    hash: [HASH_SIZE]u8,
    size: u64, // Size in bytes this block represents
};

/// Tiger Tree Hash builder using THEX specification
pub const TigerTree = struct {
    const Self = @This();

    /// Initialization options (empty for now, for future extensibility)
    pub const Options = struct {};

    allocator: std.mem.Allocator,
    blocks: std.ArrayList(Block), // Stack of partial tree nodes
    buffer: [leaf_block_size]u8,
    buffer_len: usize,
    total_size: u64,

    pub fn init(allocator: std.mem.Allocator, options: Options) Self {
        _ = options;
        return .{
            .allocator = allocator,
            .blocks = std.ArrayList(Block){},
            .buffer = undefined,
            .buffer_len = 0,
            .total_size = 0,
        };
    }

    /// One-shot hash computation
    pub fn hash(allocator: std.mem.Allocator, data: []const u8, out: *[HASH_SIZE]u8, options: Options) !void {
        var d = Self.init(allocator, options);
        defer d.deinit();
        try d.update(data);
        try d.final(out);
    }

    pub fn deinit(self: *Self) void {
        self.blocks.deinit(self.allocator);
    }

    pub fn update(self: *Self, data: []const u8) !void {
        var remaining = data;

        while (remaining.len > 0) {
            const space = leaf_block_size - self.buffer_len;
            const to_copy = @min(space, remaining.len);

            @memcpy(self.buffer[self.buffer_len..][0..to_copy], remaining[0..to_copy]);
            self.buffer_len += to_copy;
            remaining = remaining[to_copy..];

            if (self.buffer_len == leaf_block_size) {
                try self.processBlock(self.buffer[0..leaf_block_size]);
                self.buffer_len = 0;
            }
        }

        self.total_size += data.len;
    }

    pub fn final(self: *Self, out: *[HASH_SIZE]u8) !void {
        // Process any remaining buffered data
        // Note: also process for empty file case
        if (self.buffer_len > 0 or self.total_size == 0) {
            try self.processBlock(self.buffer[0..self.buffer_len]);
        }

        // Merge all remaining blocks
        while (self.blocks.items.len > 1) {
            const right = self.blocks.pop() orelse unreachable; // len > 1, so pop() cannot fail
            var left = &self.blocks.items[self.blocks.items.len - 1];
            left.hash = combineHashes(&left.hash, &right.hash);
            left.size += right.size;
        }

        if (self.blocks.items.len == 0) {
            return error.NoBlocks;
        }

        out.* = self.blocks.items[0].hash;
    }

    /// Non-destructive hash read (creates a copy before finalizing)
    pub fn peek(self: Self) ![HASH_SIZE]u8 {
        var copy = try self.clone();
        defer copy.deinit();
        var out: [HASH_SIZE]u8 = undefined;
        try copy.final(&out);
        return out;
    }

    /// Clone the current state for non-destructive operations
    fn clone(self: Self) !Self {
        var copy = Self{
            .allocator = self.allocator,
            .blocks = std.ArrayList(Block){},
            .buffer = self.buffer,
            .buffer_len = self.buffer_len,
            .total_size = self.total_size,
        };
        try copy.blocks.appendSlice(self.allocator, self.blocks.items);
        return copy;
    }

    /// Writer error type (can fail due to allocation)
    pub const Error = std.mem.Allocator.Error;

    /// Writer type for std.io integration
    pub const Writer = std.io.GenericWriter(*Self, Error, write);

    fn write(self: *Self, bytes: []const u8) Error!usize {
        try self.update(bytes);
        return bytes.len;
    }

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    /// Process a complete block (leaf hash)
    fn processBlock(self: *Self, data: []const u8) !void {
        var leaf_hash: [HASH_SIZE]u8 = undefined;

        // Leaf hash: H(0x00 || data)
        var h = Tiger.init(.{});
        h.update(&[_]u8{0x00}); // Leaf prefix
        h.update(data);
        h.final(&leaf_hash);

        try self.blocks.append(self.allocator, .{
            .hash = leaf_hash,
            .size = data.len,
        });

        try self.reduceBlocks();
    }

    /// Merge adjacent blocks of equal size
    fn reduceBlocks(self: *Self) !void {
        while (self.blocks.items.len >= 2) {
            const len = self.blocks.items.len;
            const right = &self.blocks.items[len - 1];
            const left = &self.blocks.items[len - 2];

            // Only merge blocks of equal size
            if (left.size != right.size) break;

            const right_copy = right.*;
            _ = self.blocks.pop();

            var merged = &self.blocks.items[len - 2];
            merged.hash = combineHashes(&left.hash, &right_copy.hash);
            merged.size = left.size + right_copy.size;
        }
    }

    /// Combine two hashes into internal node hash
    fn combineHashes(left: *const [HASH_SIZE]u8, right: *const [HASH_SIZE]u8) [HASH_SIZE]u8 {
        var result: [HASH_SIZE]u8 = undefined;

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
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "tiger tree - 1024 A's" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{'A'} ** 1024;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("L66Q4YVNAFWVS23X2HJIRA5ZJ7WXR3F26RSASFA", encoded);
}

test "tiger tree - 1025 A's" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{'A'} ** 1025;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("PZMRYHGY6LTBEH63ZWAHDORHSYTLO4LEFUIKHWY", encoded);
}

test "tiger tree - streaming incremental updates" {
    var tt1 = TigerTree.init(testing.allocator, .{});
    defer tt1.deinit();
    var tt2 = TigerTree.init(testing.allocator, .{});
    defer tt2.deinit();

    // One call
    const data = "test data for streaming";
    try tt1.update(data);

    // Multiple calls
    try tt2.update("test ");
    try tt2.update("data ");
    try tt2.update("for ");
    try tt2.update("streaming");

    var root1: [HASH_SIZE]u8 = undefined;
    var root2: [HASH_SIZE]u8 = undefined;
    try tt1.final(&root1);
    try tt2.final(&root2);

    try testing.expectEqualSlices(u8, &root1, &root2);
}

test "tiger tree - 2048 bytes (exactly 2 blocks)" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{0x42} ** 2048;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("4GIQEVNYCTEFRJLADAPEDVUDKZQUIE2A6BKOJQI", encoded);
}

test "tiger tree - 2049 bytes (3 blocks, triggers internal node)" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{0x42} ** 2049;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("3P66KGUMAOGUKVMR5GJE4GOWPRJLLLPZTEUI33Q", encoded);
}

test "tiger tree - 4096 bytes (exactly 4 blocks)" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{0x5A} ** 4096;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);

    // Just verify we can compute it without errors
    try testing.expect(root.len == 24);
}

test "tiger tree - large multi-level tree (8KB)" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{0x7F} ** 8192;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);

    try testing.expect(root.len == 24);
}

test "tiger tree - buffer boundary at 1024" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    // First chunk: 1023 bytes (one byte short of a block)
    const chunk1 = [_]u8{0x01} ** 1023;
    try tt.update(&chunk1);

    // Second chunk: 1 byte (completes the first block)
    const chunk2 = [_]u8{0x01};
    try tt.update(&chunk2);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    // This should produce the same result as a single 1024-byte block
    var tt2 = TigerTree.init(testing.allocator, .{});
    defer tt2.deinit();
    const data = [_]u8{0x01} ** 1024;
    try tt2.update(&data);
    var root2: [HASH_SIZE]u8 = undefined;
    try tt2.final(&root2);

    try testing.expectEqualSlices(u8, &root, &root2);
}

test "tiger tree - single byte" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{0xFF};
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expect(encoded.len == 39);
}

test "tiger tree - 10000 bytes (varied size)" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const data = [_]u8{0xAB} ** 10000;
    try tt.update(&data);

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);

    try testing.expect(root.len == 24);
}

test "tiger tree - writer interface" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const w = tt.writer();
    _ = try w.writeAll("test data");

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);

    // Verify same result as direct update
    var tt2 = TigerTree.init(testing.allocator, .{});
    defer tt2.deinit();
    try tt2.update("test data");
    var root2: [HASH_SIZE]u8 = undefined;
    try tt2.final(&root2);

    try testing.expectEqualSlices(u8, &root, &root2);
}

test "tiger tree - writer interface multiple writes" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    const w = tt.writer();
    _ = try w.writeAll("test ");
    _ = try w.writeAll("data");

    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);

    // Verify same result as direct update
    var tt2 = TigerTree.init(testing.allocator, .{});
    defer tt2.deinit();
    try tt2.update("test data");
    var root2: [HASH_SIZE]u8 = undefined;
    try tt2.final(&root2);

    try testing.expectEqualSlices(u8, &root, &root2);
}

test "tiger tree - one-shot hash" {
    var out: [HASH_SIZE]u8 = undefined;
    try TigerTree.hash(testing.allocator, "test data", &out, .{});

    // Verify same result as streaming
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();
    try tt.update("test data");
    var root: [HASH_SIZE]u8 = undefined;
    try tt.final(&root);

    try testing.expectEqualSlices(u8, &out, &root);
}

test "tiger tree - one-shot hash empty" {
    var out: [HASH_SIZE]u8 = undefined;
    try TigerTree.hash(testing.allocator, "", &out, .{});

    const encoded = try base32.encode(testing.allocator, &out);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "tiger tree - peek non-destructive" {
    var tt = TigerTree.init(testing.allocator, .{});
    defer tt.deinit();

    try tt.update("test data");

    // Peek should not consume the state
    const peeked = try tt.peek();

    // Should still be able to update and finalize
    try tt.update(" more");
    var out: [HASH_SIZE]u8 = undefined;
    try tt.final(&out);

    // Peeked value should be hash of "test data"
    var tt2 = TigerTree.init(testing.allocator, .{});
    defer tt2.deinit();
    try tt2.update("test data");
    const expected = try tt2.peek();

    try testing.expectEqualSlices(u8, &peeked, &expected);

    // Final value should be hash of "test data more"
    var tt3 = TigerTree.init(testing.allocator, .{});
    defer tt3.deinit();
    try tt3.update("test data more");
    var expected2: [HASH_SIZE]u8 = undefined;
    try tt3.final(&expected2);

    try testing.expectEqualSlices(u8, &out, &expected2);
}
