//! Base32 encoding/decoding as specified by
//! [RFC 4648](https://datatracker.ietf.org/doc/html/rfc4648).

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const window = mem.window;

pub const Error = error{
    InvalidCharacter,
    InvalidPadding,
    NoSpaceLeft,
};

const decoderWithIgnoreProto = *const fn (ignore: []const u8) Base32DecoderWithIgnore;

/// Base32 codecs
pub const Codecs = struct {
    alphabet_chars: [32]u8,
    pad_char: ?u8,
    decoderWithIgnore: decoderWithIgnoreProto,
    Encoder: Base32Encoder,
    Decoder: Base32Decoder,
};

/// The Base32 alphabet defined in
/// [RFC 4648 section 6](https://datatracker.ietf.org/doc/html/rfc4648#section-6).
pub const standard_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".*;

fn standardBase32DecoderWithIgnore(ignore: []const u8) Base32DecoderWithIgnore {
    return Base32DecoderWithIgnore.init(standard_alphabet_chars, '=', ignore);
}

/// Standard Base32 codecs, with padding, as defined in
/// [RFC 4648 section 6](https://datatracker.ietf.org/doc/html/rfc4648#section-6).
pub const standard = Codecs{
    .alphabet_chars = standard_alphabet_chars,
    .pad_char = '=',
    .decoderWithIgnore = standardBase32DecoderWithIgnore,
    .Encoder = Base32Encoder.init(standard_alphabet_chars, '='),
    .Decoder = Base32Decoder.init(standard_alphabet_chars, '='),
};

/// Standard Base32 codecs, without padding, as defined in
/// [RFC 4648 section 6](https://datatracker.ietf.org/doc/html/rfc4648#section-6).
pub const standard_no_pad = Codecs{
    .alphabet_chars = standard_alphabet_chars,
    .pad_char = null,
    .decoderWithIgnore = standardBase32DecoderWithIgnore,
    .Encoder = Base32Encoder.init(standard_alphabet_chars, null),
    .Decoder = Base32Decoder.init(standard_alphabet_chars, null),
};

/// The "Extended Hex" Base32 alphabet defined in
/// [RFC 4648 section 7](https://datatracker.ietf.org/doc/html/rfc4648#section-7).
pub const hex_alphabet_chars = "0123456789ABCDEFGHIJKLMNOPQRSTUV".*;

fn hexBase32DecoderWithIgnore(ignore: []const u8) Base32DecoderWithIgnore {
    return Base32DecoderWithIgnore.init(hex_alphabet_chars, '=', ignore);
}

/// Extended Hex Base32 codecs, with padding.
pub const hex = Codecs{
    .alphabet_chars = hex_alphabet_chars,
    .pad_char = '=',
    .decoderWithIgnore = hexBase32DecoderWithIgnore,
    .Encoder = Base32Encoder.init(hex_alphabet_chars, '='),
    .Decoder = Base32Decoder.init(hex_alphabet_chars, '='),
};

/// Extended Hex Base32 codecs, without padding.
pub const hex_no_pad = Codecs{
    .alphabet_chars = hex_alphabet_chars,
    .pad_char = null,
    .decoderWithIgnore = hexBase32DecoderWithIgnore,
    .Encoder = Base32Encoder.init(hex_alphabet_chars, null),
    .Decoder = Base32Decoder.init(hex_alphabet_chars, null),
};

pub const Base32Encoder = struct {
    alphabet_chars: [32]u8,
    pad_char: ?u8,

    pub fn init(alphabet_chars: [32]u8, pad_char: ?u8) Base32Encoder {
        var char_in_alphabet = [_]bool{false} ** 256;
        for (alphabet_chars) |c| {
            assert(!char_in_alphabet[c]);
            assert(pad_char == null or c != pad_char.?);
            char_in_alphabet[c] = true;
        }
        return Base32Encoder{
            .alphabet_chars = alphabet_chars,
            .pad_char = pad_char,
        };
    }

    /// Compute the encoded length
    pub fn calcSize(encoder: *const Base32Encoder, source_len: usize) usize {
        if (encoder.pad_char != null) {
            return @divTrunc(source_len + 4, 5) * 8;
        } else {
            return (source_len * 8 + 4) / 5;
        }
    }

    pub fn encodeWriter(encoder: *const Base32Encoder, dest: std.io.AnyWriter, source: []const u8) !void {
        var chunker = window(u8, source, 5, 5);
        while (chunker.next()) |chunk| {
            var temp: [8]u8 = undefined;
            const s = encoder.encode(&temp, chunk);
            try dest.writeAll(s);
        }
        if (chunker.remainder().len > 0) {
            var temp: [8]u8 = undefined;
            const s = encoder.encode(&temp, chunker.remainder());
            try dest.writeAll(s);
        }
    }

    /// dest.len must at least be what you get from ::calcSize.
    pub fn encode(encoder: *const Base32Encoder, dest: []u8, source: []const u8) []const u8 {
        const out_len = encoder.calcSize(source.len);
        assert(dest.len >= out_len);

        var idx: usize = 0;
        var out_idx: usize = 0;

        while (idx + 4 < source.len) : (idx += 5) {
            const b0 = source[idx];
            const b1 = source[idx + 1];
            const b2 = source[idx + 2];
            const b3 = source[idx + 3];
            const b4 = source[idx + 4];

            dest[out_idx] = encoder.alphabet_chars[(b0 >> 3) & 0x1F];
            dest[out_idx + 1] = encoder.alphabet_chars[((b0 & 0x07) << 2) | ((b1 >> 6) & 0x03)];
            dest[out_idx + 2] = encoder.alphabet_chars[(b1 >> 1) & 0x1F];
            dest[out_idx + 3] = encoder.alphabet_chars[((b1 & 0x01) << 4) | ((b2 >> 4) & 0x0F)];
            dest[out_idx + 4] = encoder.alphabet_chars[((b2 & 0x0F) << 1) | ((b3 >> 7) & 0x01)];
            dest[out_idx + 5] = encoder.alphabet_chars[(b3 >> 2) & 0x1F];
            dest[out_idx + 6] = encoder.alphabet_chars[((b3 & 0x03) << 3) | ((b4 >> 5) & 0x07)];
            dest[out_idx + 7] = encoder.alphabet_chars[b4 & 0x1F];

            out_idx += 8;
        }

        if (idx < source.len) {
            const b0 = source[idx];
            dest[out_idx] = encoder.alphabet_chars[(b0 >> 3) & 0x1F];

            if (idx + 1 < source.len) {
                const b1 = source[idx + 1];
                dest[out_idx + 1] = encoder.alphabet_chars[((b0 & 0x07) << 2) | ((b1 >> 6) & 0x03)];
                dest[out_idx + 2] = encoder.alphabet_chars[(b1 >> 1) & 0x1F];

                if (idx + 2 < source.len) {
                    const b2 = source[idx + 2];
                    dest[out_idx + 3] = encoder.alphabet_chars[((b1 & 0x01) << 4) | ((b2 >> 4) & 0x0F)];

                    if (idx + 3 < source.len) {
                        const b3 = source[idx + 3];
                        dest[out_idx + 4] = encoder.alphabet_chars[((b2 & 0x0F) << 1) | ((b3 >> 7) & 0x01)];
                        dest[out_idx + 5] = encoder.alphabet_chars[(b3 >> 2) & 0x1F];
                        dest[out_idx + 6] = encoder.alphabet_chars[(b3 & 0x03) << 3];
                        out_idx += 7;
                    } else {
                        dest[out_idx + 4] = encoder.alphabet_chars[(b2 & 0x0F) << 1];
                        out_idx += 5;
                    }
                } else {
                    dest[out_idx + 3] = encoder.alphabet_chars[(b1 & 0x01) << 4];
                    out_idx += 4;
                }
            } else {
                dest[out_idx + 1] = encoder.alphabet_chars[(b0 & 0x07) << 2];
                out_idx += 2;
            }
        }

        if (encoder.pad_char) |pad_char| {
            for (dest[out_idx..out_len]) |*pad| {
                pad.* = pad_char;
            }
        }

        return dest[0..out_len];
    }
};

pub const Base32Decoder = struct {
    pub const invalid_char: u8 = 0xff;

    /// e.g. 'A' => 0.
    /// `invalid_char` for any value not in the 32 alphabet chars.
    char_to_index: [256]u8,
    pad_char: ?u8,

    pub fn init(alphabet_chars: [32]u8, pad_char: ?u8) Base32Decoder {
        var result = Base32Decoder{
            .char_to_index = [_]u8{invalid_char} ** 256,
            .pad_char = pad_char,
        };

        var char_in_alphabet = [_]bool{false} ** 256;
        for (alphabet_chars, 0..) |c, i| {
            assert(!char_in_alphabet[c]);
            assert(pad_char == null or c != pad_char.?);

            result.char_to_index[c] = @as(u8, @intCast(i));
            char_in_alphabet[c] = true;
        }
        return result;
    }

    /// Return the maximum possible decoded size for a given input length.
    /// `InvalidPadding` is returned if the input length is not valid.
    pub fn calcSizeUpperBound(decoder: *const Base32Decoder, source_len: usize) Error!usize {
        var result = source_len / 8 * 5;
        const leftover = source_len % 8;
        if (decoder.pad_char != null) {
            if (leftover != 0) return error.InvalidPadding;
        } else {
            switch (leftover) {
                0 => {},
                2 => result += 1,
                4 => result += 2,
                5 => result += 3,
                7 => result += 4,
                else => return error.InvalidPadding,
            }
        }
        return result;
    }

    /// Return the exact decoded size for a slice.
    /// `InvalidPadding` is returned if the input length is not valid.
    pub fn calcSizeForSlice(decoder: *const Base32Decoder, source: []const u8) Error!usize {
        const source_len = source.len;
        var result = try decoder.calcSizeUpperBound(source_len);
        if (decoder.pad_char) |pad_char| {
            var padding: usize = 0;
            var i = source_len;
            while (i > 0) {
                i -= 1;
                if (source[i] == pad_char) {
                    padding += 1;
                } else {
                    break;
                }
            }
            switch (padding) {
                0 => {},
                1 => result -= 1,
                3 => result -= 2,
                4 => result -= 3,
                6 => result -= 4,
                else => return error.InvalidPadding,
            }
        }
        return result;
    }

    /// dest.len must be what you get from ::calcSize.
    /// Invalid characters result in `error.InvalidCharacter`.
    /// Invalid padding results in `error.InvalidPadding`.
    pub fn decode(decoder: *const Base32Decoder, dest: []u8, source: []const u8) Error!void {
        if (decoder.pad_char != null and source.len % 8 != 0) return error.InvalidPadding;

        var acc: u64 = 0;
        var acc_len: u6 = 0;
        var dest_idx: usize = 0;
        var leftover_idx: ?usize = null;

        for (source, 0..) |c, i| {
            const d = decoder.char_to_index[c];
            if (d == invalid_char) {
                if (decoder.pad_char == null or c != decoder.pad_char.?) return error.InvalidCharacter;
                leftover_idx = i;
                break;
            }
            acc = (acc << 5) | d;
            acc_len += 5;
            if (acc_len >= 8) {
                acc_len -= 8;
                if (dest_idx >= dest.len) return error.NoSpaceLeft;
                dest[dest_idx] = @as(u8, @truncate(acc >> acc_len));
                dest_idx += 1;
            }
        }

        if (acc_len >= 5 or (acc & (@as(u64, 1) << acc_len) - 1) != 0) {
            return error.InvalidPadding;
        }

        if (leftover_idx == null) return;
        const leftover = source[leftover_idx.?..];
        if (decoder.pad_char) |pad_char| {
            for (leftover) |c| {
                if (c != pad_char) {
                    return error.InvalidPadding;
                }
            }
        }
    }
};

pub const Base32DecoderWithIgnore = struct {
    decoder: Base32Decoder,
    char_is_ignored: [256]bool,

    pub fn init(alphabet_chars: [32]u8, pad_char: ?u8, ignore_chars: []const u8) Base32DecoderWithIgnore {
        var result = Base32DecoderWithIgnore{
            .decoder = Base32Decoder.init(alphabet_chars, pad_char),
            .char_is_ignored = [_]bool{false} ** 256,
        };
        for (ignore_chars) |c| {
            assert(result.decoder.char_to_index[c] == Base32Decoder.invalid_char);
            assert(!result.char_is_ignored[c]);
            assert(result.decoder.pad_char != c);
            result.char_is_ignored[c] = true;
        }
        return result;
    }

    pub fn calcSizeUpperBound(decoder_with_ignore: *const Base32DecoderWithIgnore, source_len: usize) usize {
        var result = source_len / 8 * 5;
        if (decoder_with_ignore.decoder.pad_char == null) {
            const leftover = source_len % 8;
            result += (leftover * 5 + 7) / 8;
        }
        return result + 5;
    }

    pub fn decode(decoder_with_ignore: *const Base32DecoderWithIgnore, dest: []u8, source: []const u8) Error!usize {
        const decoder = &decoder_with_ignore.decoder;
        var acc: u64 = 0;
        var acc_len: u6 = 0;
        var dest_idx: usize = 0;
        var leftover_idx: ?usize = null;

        for (source, 0..) |c, src_idx| {
            if (decoder_with_ignore.char_is_ignored[c]) continue;
            const d = decoder.char_to_index[c];
            if (d == Base32Decoder.invalid_char) {
                if (decoder.pad_char == null or c != decoder.pad_char.?) return error.InvalidCharacter;
                leftover_idx = src_idx;
                break;
            }
            acc = (acc << 5) | d;
            acc_len += 5;
            if (acc_len >= 8) {
                if (dest_idx == dest.len) return error.NoSpaceLeft;
                acc_len -= 8;
                dest[dest_idx] = @as(u8, @truncate(acc >> acc_len));
                dest_idx += 1;
            }
        }

        if (acc_len >= 5 or (acc & (@as(u64, 1) << acc_len) - 1) != 0) {
            return error.InvalidPadding;
        }

        if (leftover_idx != null) {
            const leftover = source[leftover_idx.?..];
            if (decoder.pad_char) |pad_char| {
                for (leftover) |c| {
                    if (decoder_with_ignore.char_is_ignored[c]) continue;
                    if (c != pad_char) {
                        return error.InvalidPadding;
                    }
                }
            }
        }
        return dest_idx;
    }
};

test "base32 standard" {
    const codecs = standard;
    try testAllApis(codecs, "", "");
    try testAllApis(codecs, "f", "MY======");
    try testAllApis(codecs, "fo", "MZXQ====");
    try testAllApis(codecs, "foo", "MZXW6===");
    try testAllApis(codecs, "foob", "MZXW6YQ=");
    try testAllApis(codecs, "fooba", "MZXW6YTB");
    try testAllApis(codecs, "foobar", "MZXW6YTBOI======");
}

test "base32 standard no pad" {
    const codecs = standard_no_pad;
    try testAllApis(codecs, "", "");
    try testAllApis(codecs, "f", "MY");
    try testAllApis(codecs, "fo", "MZXQ");
    try testAllApis(codecs, "foo", "MZXW6");
    try testAllApis(codecs, "foob", "MZXW6YQ");
    try testAllApis(codecs, "fooba", "MZXW6YTB");
    try testAllApis(codecs, "foobar", "MZXW6YTBOI");
}

fn testAllApis(codecs: Codecs, expected_decoded: []const u8, expected_encoded: []const u8) !void {
    {
        var buffer: [0x100]u8 = undefined;
        const encoded = codecs.Encoder.encode(&buffer, expected_decoded);
        try testing.expectEqualSlices(u8, expected_encoded, encoded);
    }
    {
        var buffer: [0x100]u8 = undefined;
        const decoded = buffer[0..try codecs.Decoder.calcSizeForSlice(expected_encoded)];
        try codecs.Decoder.decode(decoded, expected_encoded);
        try testing.expectEqualSlices(u8, expected_decoded, decoded);
    }
}
