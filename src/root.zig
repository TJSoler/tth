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

/// Compute Tiger Tree Hash for given data. Returns 24-byte hash.
pub fn compute(allocator: std.mem.Allocator, data: []const u8) ![24]u8 {
    var tree = TigerTree.init(allocator, .{});
    defer tree.deinit();

    try tree.update(data);
    var hash: [24]u8 = undefined;
    try tree.final(&hash);
    return hash;
}

/// Compute Tiger Tree Hash for a file. Returns 24-byte hash.
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

const testing = std.testing;

test "public API - compute empty data" {
    const hash = try compute(testing.allocator, "");
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &hash);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "public API - compute simple data" {
    const data = "Hello, World!";
    const hash = try compute(testing.allocator, data);

    try testing.expect(hash.len == digest_length);
    try testing.expect(hash.len == 24);
}

test "public API - compute large data" {
    const data = [_]u8{0xAB} ** 10000;
    const hash = try compute(testing.allocator, &data);

    try testing.expect(hash.len == digest_length);
}

test "public API - compute consistency" {
    const data = "Test data for consistency check";
    const hash1 = try compute(testing.allocator, data);
    const hash2 = try compute(testing.allocator, data);

    try testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "public API - computeFromFile with temp file" {
    // Create a temporary file
    const test_data = "This is test data for file hashing";
    const temp_file_path = "test_temp_file.txt";

    const file = try std.fs.cwd().createFile(temp_file_path, .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(temp_file_path) catch {};
    }

    try file.writeAll(test_data);
    try file.sync();

    // Compute hash from file
    const hash_from_file = try computeFromFile(testing.allocator, temp_file_path);

    // Compute hash from data directly
    const hash_from_data = try compute(testing.allocator, test_data);

    try testing.expectEqualSlices(u8, &hash_from_file, &hash_from_data);
}

test "public API - computeFromFile empty file" {
    const temp_file_path = "test_empty_file.txt";

    const file = try std.fs.cwd().createFile(temp_file_path, .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(temp_file_path) catch {};
    }

    const hash = try computeFromFile(testing.allocator, temp_file_path);
    var buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&buf, &hash);

    try testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", encoded);
}

test "public API - computeFromFile large file" {
    const temp_file_path = "test_large_file.bin";

    const file = try std.fs.cwd().createFile(temp_file_path, .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(temp_file_path) catch {};
    }

    // Write 100KB of data
    const chunk = [_]u8{0x42} ** 1024;
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try file.writeAll(&chunk);
    }
    try file.sync();

    const hash = try computeFromFile(testing.allocator, temp_file_path);

    try testing.expect(hash.len == digest_length);
}

test "public API - error on non-existent file" {
    const result = computeFromFile(testing.allocator, "non_existent_file_xyz.txt");
    try testing.expectError(error.FileNotFound, result);
}

test "public API - Tiger direct usage" {
    var h = Tiger.init(.{});
    h.update("test");
    var digest: [digest_length]u8 = undefined;
    h.final(&digest);

    try testing.expect(digest.len == digest_length);
}

test "public API - TigerTree direct usage" {
    var tree = TigerTree.init(testing.allocator, .{});
    defer tree.deinit();

    try tree.update("test data");
    var hash: [24]u8 = undefined;
    try tree.final(&hash);

    try testing.expect(hash.len == digest_length);
}

test "public API - full integration with base32" {
    const data = "Integration test data";
    const hash = try compute(testing.allocator, data);
    var encode_buf: [39]u8 = undefined;
    const encoded = base32.standard_no_pad.Encoder.encode(&encode_buf, &hash);

    // Verify encoded length
    try testing.expectEqual(@as(usize, 39), encoded.len);

    // Decode and verify round-trip
    var decode_buf: [24]u8 = undefined;
    try base32.standard_no_pad.Decoder.decode(&decode_buf, encoded);

    try testing.expectEqualSlices(u8, &hash, &decode_buf);
}
