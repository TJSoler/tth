//! base32.zig - RFC 4648 Base32 encoding for Tiger Tree Hash
//!
//! Implements RFC 4648 base32 encoding as used by DC++ for TTH hashes.
//! The alphabet is A-Z (values 0-25) and 2-7 (values 26-31).

const std = @import("std");

/// RFC 4648 Base32 alphabet
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/// Encode bytes to base32 string
/// For 24 bytes (TTH), produces 39 characters (no padding)
/// Returns allocated string that must be freed by caller
pub fn encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    // Each 5 bytes → 8 base32 chars
    // For partial groups, we get ceil(data.len * 8 / 5) characters
    const output_len = (data.len * 8 + 4) / 5;
    var result = try allocator.alloc(u8, output_len);

    var bits: u64 = 0;
    var bits_count: u6 = 0;
    var out_idx: usize = 0;

    for (data) |byte| {
        bits = (bits << 8) | byte;
        bits_count += 8;

        while (bits_count >= 5) {
            bits_count -= 5;
            const index = @as(u5, @intCast((bits >> bits_count) & 0x1F));
            result[out_idx] = alphabet[index];
            out_idx += 1;
        }
    }

    // Handle remaining bits (if any)
    if (bits_count > 0) {
        const index = @as(u5, @intCast((bits << (5 - bits_count)) & 0x1F));
        result[out_idx] = alphabet[index];
    }

    return result;
}

/// Decode base32 string to bytes
/// Returns allocated byte array that must be freed by caller
pub fn decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const output_len = (data.len * 5) / 8;
    var result = try allocator.alloc(u8, output_len);
    errdefer allocator.free(result);
    @memset(result, 0);

    var bits: u64 = 0;
    var bits_count: u6 = 0;
    var out_idx: usize = 0;

    for (data) |char| {
        const value = try charToValue(char);
        bits = (bits << 5) | value;
        bits_count += 5;

        if (bits_count >= 8) {
            bits_count -= 8;
            result[out_idx] = @intCast((bits >> bits_count) & 0xFF);
            out_idx += 1;
        }
    }

    return result;
}

/// Convert a base32 character to its 5-bit value
fn charToValue(char: u8) !u5 {
    return switch (char) {
        'A'...'Z' => @intCast(char - 'A'),
        '2'...'7' => @intCast(char - '2' + 26),
        else => error.InvalidBase32Character,
    };
}

const testing = std.testing;

test "base32 - encode empty" {
    const data = [_]u8{};
    const result = try encode(testing.allocator, &data);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("", result);
}

test "base32 - encode/decode round-trip" {
    const original = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A };
    const encoded = try encode(testing.allocator, &original);
    defer testing.allocator.free(encoded);

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);

    try testing.expectEqualSlices(u8, &original, decoded);
}

test "base32 - TTH length" {
    // 24 bytes → 39 characters (no padding)
    const data = [_]u8{0} ** 24;
    const encoded = try encode(testing.allocator, &data);
    defer testing.allocator.free(encoded);
    try testing.expectEqual(@as(usize, 39), encoded.len);
}

test "base32 - known test vectors" {
    // Test vector: "abc" -> "MFRGG==="  (but without padding -> "MFRGG")
    const input = "abc";
    const encoded = try encode(testing.allocator, input);
    defer testing.allocator.free(encoded);

    // "abc" in base32 should start with "MFRGG"
    try testing.expectEqualStrings("MFRGG", encoded[0..5]);

    // Decode back
    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, input, decoded);
}

test "base32 - invalid character" {
    const invalid = "ABC@";
    const result = decode(testing.allocator, invalid);
    try testing.expectError(error.InvalidBase32Character, result);
}

test "base32 - RFC 4648 test vectors" {
    // Test vectors from RFC 4648
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "f", .expected = "MY" },
        .{ .input = "fo", .expected = "MZXQ" },
        .{ .input = "foo", .expected = "MZXW6" },
        .{ .input = "foob", .expected = "MZXW6YQ" },
        .{ .input = "fooba", .expected = "MZXW6YTB" },
        .{ .input = "foobar", .expected = "MZXW6YTBOI" },
    };

    for (test_cases) |case| {
        const encoded = try encode(testing.allocator, case.input);
        defer testing.allocator.free(encoded);
        try testing.expectEqualStrings(case.expected, encoded);

        const decoded = try decode(testing.allocator, encoded);
        defer testing.allocator.free(decoded);
        try testing.expectEqualSlices(u8, case.input, decoded);
    }
}

test "base32 - single byte encoding" {
    const data = [_]u8{0xFF};
    const encoded = try encode(testing.allocator, &data);
    defer testing.allocator.free(encoded);

    try testing.expect(encoded.len == 2);

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}

test "base32 - 5 bytes encoding (clean multiple)" {
    const data = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A };
    const encoded = try encode(testing.allocator, &data);
    defer testing.allocator.free(encoded);

    // 5 bytes -> 8 characters
    try testing.expectEqual(@as(usize, 8), encoded.len);

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}

test "base32 - 100 bytes encoding" {
    const data = [_]u8{0xAB} ** 100;
    const encoded = try encode(testing.allocator, &data);
    defer testing.allocator.free(encoded);

    // 100 bytes -> 160 characters
    try testing.expectEqual(@as(usize, 160), encoded.len);

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}

test "base32 - all zeros" {
    const data = [_]u8{0} ** 24;
    const encoded = try encode(testing.allocator, &data);
    defer testing.allocator.free(encoded);

    // All zeros should encode to all 'A's
    for (encoded) |c| {
        try testing.expectEqual(@as(u8, 'A'), c);
    }

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}

test "base32 - all ones" {
    const data = [_]u8{0xFF} ** 24;
    const encoded = try encode(testing.allocator, &data);
    defer testing.allocator.free(encoded);

    try testing.expectEqual(@as(usize, 39), encoded.len);

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}

test "base32 - alphabet coverage" {
    // Ensure all characters in alphabet are valid
    const alphabet_str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    const decoded = try decode(testing.allocator, alphabet_str);
    defer testing.allocator.free(decoded);

    const re_encoded = try encode(testing.allocator, decoded);
    defer testing.allocator.free(re_encoded);

    try testing.expectEqualStrings(alphabet_str, re_encoded);
}

test "base32 - decode invalid lowercase" {
    // Our implementation should reject lowercase
    const lowercase = "abc";
    const result = decode(testing.allocator, lowercase);
    try testing.expectError(error.InvalidBase32Character, result);
}

test "base32 - empty round-trip" {
    const empty = [_]u8{};
    const encoded = try encode(testing.allocator, &empty);
    defer testing.allocator.free(encoded);
    try testing.expectEqual(@as(usize, 0), encoded.len);

    const decoded = try decode(testing.allocator, encoded);
    defer testing.allocator.free(decoded);
    try testing.expectEqual(@as(usize, 0), decoded.len);
}
