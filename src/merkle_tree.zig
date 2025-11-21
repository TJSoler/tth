//! merkle_tree.zig - Merkle tree for Tiger Tree Hash (TTH)
//!
//! Based on THEX specification and EiskaltDC++ implementation.
//! Uses incremental tree building with 1024-byte leaf blocks.

const std = @import("std");
const Tiger = @import("tiger.zig").Tiger;

/// THEX standard leaf block size
pub const BLOCK_SIZE = 1024;

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

    allocator: std.mem.Allocator,
    blocks: std.ArrayList(Block), // Stack of partial tree nodes
    buffer: [BLOCK_SIZE]u8,
    buffer_len: usize,
    total_size: u64,

    /// Initialize TigerTree builder
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .blocks = std.ArrayList(Block){},
            .buffer = undefined,
            .buffer_len = 0,
            .total_size = 0,
        };
    }

    /// Release allocated memory
    pub fn deinit(self: *Self) void {
        self.blocks.deinit(self.allocator);
    }

    /// Update tree with new data
    pub fn update(self: *Self, data: []const u8) !void {
        var remaining = data;

        while (remaining.len > 0) {
            const space = BLOCK_SIZE - self.buffer_len;
            const to_copy = @min(space, remaining.len);

            @memcpy(self.buffer[self.buffer_len..][0..to_copy], remaining[0..to_copy]);
            self.buffer_len += to_copy;
            remaining = remaining[to_copy..];

            if (self.buffer_len == BLOCK_SIZE) {
                try self.processBlock(self.buffer[0..BLOCK_SIZE]);
                self.buffer_len = 0;
            }
        }

        self.total_size += data.len;
    }

    /// Finalize tree and return root hash
    pub fn finalize(self: *Self) ![HASH_SIZE]u8 {
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

        return self.blocks.items[0].hash;
    }

    /// Process a complete block (leaf hash)
    fn processBlock(self: *Self, data: []const u8) !void {
        var leaf_hash: [HASH_SIZE]u8 = undefined;

        // Leaf hash: H(0x00 || data)
        var h = Tiger.init();
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
        var h = Tiger.init();
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
    var tt = TigerTree.init(testing.allocator);
    defer tt.deinit();

    const root = try tt.finalize();
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "tiger tree - 1024 A's" {
    var tt = TigerTree.init(testing.allocator);
    defer tt.deinit();

    const data = [_]u8{'A'} ** 1024;
    try tt.update(&data);

    const root = try tt.finalize();
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("L66Q4YVNAFWVS23X2HJIRA5ZJ7WXR3F26RSASFA", encoded);
}

test "tiger tree - 1025 A's" {
    var tt = TigerTree.init(testing.allocator);
    defer tt.deinit();

    const data = [_]u8{'A'} ** 1025;
    try tt.update(&data);

    const root = try tt.finalize();
    const encoded = try base32.encode(testing.allocator, &root);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings("PZMRYHGY6LTBEH63ZWAHDORHSYTLO4LEFUIKHWY", encoded);
}
