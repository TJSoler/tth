//! TTH (Tiger Tree Hash) library
//!
//! This library provides a complete implementation of Tiger Tree Hash (TTH)
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

test {
    std.testing.refAllDecls(@This());
}

const testing = std.testing;

test "public API - hash empty data" {
    var hash: [digest_length]u8 = undefined;
    TigerTree.hash("", &hash, .{});
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &hash);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "public API - hash simple data" {
    const data = "Hello, World!";
    var hash: [digest_length]u8 = undefined;
    TigerTree.hash(data, &hash, .{});

    try testing.expect(hash.len == digest_length);
    try testing.expect(hash.len == 24);
}

test "public API - hash large data" {
    const data = [_]u8{0xAB} ** 10000;
    var hash: [digest_length]u8 = undefined;
    TigerTree.hash(&data, &hash, .{});

    try testing.expect(hash.len == digest_length);
}

test "public API - hash consistency" {
    const data = "Test data for consistency check";
    var hash1: [digest_length]u8 = undefined;
    var hash2: [digest_length]u8 = undefined;
    TigerTree.hash(data, &hash1, .{});
    TigerTree.hash(data, &hash2, .{});

    try testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "public API - Tiger direct usage" {
    var h = Tiger.init(.{});
    h.update("test");
    var digest: [digest_length]u8 = undefined;
    h.final(&digest);

    try testing.expect(digest.len == digest_length);
}

test "public API - TigerTree direct usage" {
    var tree = TigerTree.init(.{});

    tree.update("test data");
    var hash: [24]u8 = undefined;
    tree.final(&hash);

    try testing.expect(hash.len == digest_length);
}

test "public API - full integration with base32" {
    const data = "Integration test data";
    var hash: [digest_length]u8 = undefined;
    TigerTree.hash(data, &hash, .{});
    var encode_buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&encode_buf, &hash);

    // Verify encoded length
    try testing.expectEqual(@as(usize, 39), encoded.len);

    // Decode and verify round-trip
    var decode_buf: [24]u8 = undefined;
    try base32.standard_no_pad.Decoder.decode(&decode_buf, encoded);

    try testing.expectEqualSlices(u8, &hash, &decode_buf);
}
