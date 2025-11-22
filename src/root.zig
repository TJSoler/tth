//! TTH (Tiger Tree Hash) library
//!
//! This library provides a complete implementation of Tiger Tree Hash (TTH),
//! commonly used in peer-to-peer file sharing protocols like DC++.
//!
//! The implementation includes:
//! - Pure Zig Tiger hash algorithm
//! - Merkle tree construction following the THEX specification
//! - RFC 4648 Base32 encoding/decoding for hash representation

const std = @import("std");

/// TTH library version
pub const version = "0.1.0";

/// Tiger hash algorithm implementation
const tiger = @import("tiger.zig");

/// Tiger Tree Hash (TTH) using Merkle tree
const merkle = @import("merkle_tree.zig");

/// Base32 encoding/decoding (RFC 4648) for TTH hashes
pub const base32 = @import("base32.zig");

/// Re-export commonly used types for convenience
pub const Tiger = tiger.Tiger;
pub const TigerTree = merkle.TigerTree;

/// Tiger hash digest length (24 bytes / 192 bits)
pub const digest_length = tiger.digest_length;

/// Tiger hash block size (64 bytes / 512 bits)
pub const block_length = tiger.block_length;

/// THEX standard leaf block size for Tiger Tree Hash (1024 bytes)
pub const leaf_block_size = merkle.leaf_block_size;

/// Compute Tiger Tree Hash for given data
pub fn compute(allocator: std.mem.Allocator, data: []const u8) ![24]u8 {
    var tree = TigerTree.init(allocator, .{});
    defer tree.deinit();

    try tree.update(data);
    var hash: [24]u8 = undefined;
    try tree.final(&hash);
    return hash;
}

/// Compute Tiger Tree Hash for a file
pub fn computeFromFile(allocator: std.mem.Allocator, file_path: []const u8) ![24]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var tree = TigerTree.init(allocator, .{});
    defer tree.deinit();

    const buffer_size = 64 * 1024;
    var buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    while (true) {
        const bytes_read = try file.read(buffer);
        if (bytes_read == 0) break;
        try tree.update(buffer[0..bytes_read]);
    }

    var hash: [24]u8 = undefined;
    try tree.final(&hash);
    return hash;
}

test {
    std.testing.refAllDecls(@This());
}
