//! TTH (Tiger Tree Hash) - Pure Zig implementation
//!
//! Provides Tiger hash, Tiger Tree Hash (THEX Merkle tree), and Base32 encoding.
//!
//! **SECURITY WARNING**: Tiger hash is not cryptographically secure.
//! Use only for file integrity checking, not security-critical applications.

const std = @import("std");
const tiger = @import("tiger.zig");
const merkle = @import("merkle_tree.zig");

/// Base32 encoding/decoding per RFC 4648
pub const base32 = @import("base32.zig");

/// Tiger hash algorithm
pub const Tiger = tiger.Tiger;

/// Tiger Tree Hash using THEX Merkle tree
pub const TigerTree = merkle.TigerTree;

/// Tiger hash output size (192 bits)
pub const digest_length = Tiger.digest_length;

/// Tiger hash block size (512 bits)
pub const block_length = Tiger.block_length;

/// THEX leaf block size
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
