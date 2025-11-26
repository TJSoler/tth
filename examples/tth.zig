//! Command-line interface for computing Tiger Tree Hash (TTH) of files
//!
//! Usage: tth <file>

const std = @import("std");
const tth = @import("tth");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file>\n", .{args[0]});
        std.debug.print("Computes the Tiger Tree Hash (TTH) of a file\n", .{});
        return;
    }

    const file_path = args[1];

    // Compute TTH
    const hash = try tth.computeFromFile(allocator, file_path);

    // Encode to Base32
    var buf: [39]u8 = undefined;
    const encoded = tth.base32.standard_no_pad.Encoder.encode(&buf, &hash);

    std.debug.print("TTH ({s}): {s}\n", .{ file_path, encoded });
}

test "basic TTH functionality" {
    const allocator = std.testing.allocator;

    // Test empty data
    const empty_hash = try tth.compute(allocator, "");
    var empty_buf: [39]u8 = undefined;
    const empty_encoded = tth.base32.standard_no_pad.Encoder.encode(&empty_buf, &empty_hash);

    try std.testing.expectEqualStrings("LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ", empty_encoded);

    // Test simple data
    const data = "abc";
    const hash = try tth.compute(allocator, data);
    var buf: [39]u8 = undefined;
    const encoded = tth.base32.standard_no_pad.Encoder.encode(&buf, &hash);
    try std.testing.expectEqualStrings("ASD4UJSEH5M47PDYB46KBTSQTSGDKLBHYXOMUIA", encoded);
}
