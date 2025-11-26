//! TTH Benchmark Suite
//!
//! Measures throughput of Tiger hash, TigerTree, and Base32 operations.
//!
//! Run with: zig build bench -Doptimize=ReleaseFast -- [options]
//!
//! Options:
//!   --filter [name]   Run only benchmarks matching name
//!   --json            Output results as JSON

const std = @import("std");
const tth = @import("root.zig");
const builtin = @import("builtin");
const time = std.time;
const Timer = time.Timer;
const mem = std.mem;

const KiB = 1024;
const MiB = 1024 * KiB;

/// Scale down data sizes in debug mode for faster iteration
fn mode(comptime x: comptime_int) comptime_int {
    return if (builtin.mode == .Debug) x / 64 else x;
}

const Crypto = struct {
    ty: type,
    name: []const u8,
};

const hashes = [_]Crypto{
    .{ .ty = tth.Tiger, .name = "tiger" },
    .{ .ty = tth.TigerTree, .name = "tigertree" },
};

const block_size: usize = 8192;

/// Benchmark hash throughput
pub fn benchmarkHash(comptime Hash: anytype, comptime bytes: comptime_int) !u64 {
    const blocks_count = bytes / block_size;
    var block: [block_size]u8 = undefined;

    var prng = std.Random.DefaultPrng.init(42);
    prng.random().bytes(&block);

    var h = Hash.init(.{});

    var timer = try Timer.start();
    const start = timer.lap();

    for (0..blocks_count) |_| {
        h.update(&block);
    }

    var final: [Hash.digest_length]u8 = undefined;
    h.final(&final);
    mem.doNotOptimizeAway(final);

    const end = timer.read();

    const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    const throughput = @as(u64, @intFromFloat(bytes / elapsed_s));

    return throughput;
}

/// Benchmark Base32 encoding throughput
pub fn benchmarkBase32Encode(comptime iterations: comptime_int) !u64 {
    const data = [_]u8{0x42} ** 24; // TTH hash size

    var timer = try Timer.start();
    const start = timer.lap();

    for (0..iterations) |_| {
        var buf: [39]u8 = undefined;
        const encoded = tth.base32.standard_no_pad.Encoder.encode(&buf, &data);
        mem.doNotOptimizeAway(encoded);
    }

    const end = timer.read();

    const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    return @as(u64, @intFromFloat(iterations / elapsed_s));
}

/// Benchmark Base32 decoding throughput
pub fn benchmarkBase32Decode(comptime iterations: comptime_int) !u64 {
    const encoded = "LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ";

    var timer = try Timer.start();
    const start = timer.lap();

    for (0..iterations) |_| {
        var buf: [24]u8 = undefined;
        tth.base32.standard_no_pad.Decoder.decode(&buf, encoded) catch unreachable;
        mem.doNotOptimizeAway(&buf);
    }

    const end = timer.read();

    const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
    return @as(u64, @intFromFloat(iterations / elapsed_s));
}

const OutputFormat = enum { human, json };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    var filter: ?[]const u8 = null;
    var output_format = OutputFormat.human;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "--filter")) {
            i += 1;
            if (i < args.len) {
                filter = args[i];
            }
        } else if (mem.eql(u8, args[i], "--json")) {
            output_format = .json;
        } else if (mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            i += 1;
            if (mem.eql(u8, args[i], "json")) {
                output_format = .json;
            }
        }
    }

    const stdout = std.fs.File.stdout().deprecatedWriter();

    if (output_format == .human) {
        try stdout.print("\nTTH Benchmark Suite\n", .{});
        try stdout.print("===================\n", .{});
        try stdout.print("Build mode: {s}\n\n", .{@tagName(builtin.mode)});
    }

    // Collect results for JSON output
    var tiger_throughput: u64 = 0;
    var tigertree_throughput: u64 = 0;
    var encode_ops: u64 = 0;
    var decode_ops: u64 = 0;

    // Hash benchmarks
    inline for (hashes) |H| {
        if (filter == null or mem.indexOf(u8, H.name, filter.?) != null) {
            const throughput = try benchmarkHash(H.ty, mode(128 * MiB));

            if (mem.eql(u8, H.name, "tiger")) {
                tiger_throughput = throughput;
            } else if (mem.eql(u8, H.name, "tigertree")) {
                tigertree_throughput = throughput;
            }

            if (output_format == .human) {
                try stdout.print("{s:>12}: {:10} MiB/s\n", .{ H.name, throughput / MiB });
            }
        }
    }

    // Base32 benchmarks
    const base32_filter_match = filter == null or mem.indexOf(u8, "base32", filter.?) != null;
    if (base32_filter_match) {
        encode_ops = try benchmarkBase32Encode(mode(10_000_000));
        decode_ops = try benchmarkBase32Decode(mode(10_000_000));

        if (output_format == .human) {
            try stdout.print("{s:>12}: {:10} op/s\n", .{ "base32-enc", encode_ops });
            try stdout.print("{s:>12}: {:10} op/s\n", .{ "base32-dec", decode_ops });
        }
    }

    if (output_format == .human) {
        try stdout.print("\n", .{});
    } else {
        // JSON output for CI comparison
        try stdout.print("{{\n", .{});
        try stdout.print("  \"tiger\": [{{\n", .{});
        try stdout.print("    \"name\": \"128 MiB\",\n", .{});
        try stdout.print("    \"size_bytes\": {d},\n", .{mode(128 * MiB)});
        try stdout.print("    \"throughput_bytes_per_sec\": {d}\n", .{tiger_throughput});
        try stdout.print("  }}],\n", .{});
        try stdout.print("  \"tiger_tree\": [{{\n", .{});
        try stdout.print("    \"name\": \"128 MiB\",\n", .{});
        try stdout.print("    \"size_bytes\": {d},\n", .{mode(128 * MiB)});
        try stdout.print("    \"throughput_bytes_per_sec\": {d}\n", .{tigertree_throughput});
        try stdout.print("  }}],\n", .{});
        try stdout.print("  \"base32_encode_ops\": {d},\n", .{encode_ops});
        try stdout.print("  \"base32_decode_ops\": {d}\n", .{decode_ops});
        try stdout.print("}}\n", .{});
    }
}
