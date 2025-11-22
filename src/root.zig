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
pub const BLOCK_SIZE = merkle.BLOCK_SIZE;

/// Compute Tiger Tree Hash for given data
/// Returns the root hash as a 24-byte array
pub fn compute(allocator: std.mem.Allocator, data: []const u8) ![24]u8 {
    var tree = TigerTree.init(allocator);
    defer tree.deinit();

    try tree.update(data);
    return try tree.finalize();
}

/// Compute Tiger Tree Hash for a file
/// Returns the root hash as a 24-byte array
pub fn computeFromFile(allocator: std.mem.Allocator, file_path: []const u8) ![24]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var tree = TigerTree.init(allocator);
    defer tree.deinit();

    const buffer_size = 64 * 1024; // 64KB buffer
    var buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(buffer);

    while (true) {
        const bytes_read = try file.read(buffer);
        if (bytes_read == 0) break;
        try tree.update(buffer[0..bytes_read]);
    }

    return try tree.finalize();
}

test {
    std.testing.refAllDecls(@This());
}
