//! TTH Benchmark Suite
//!
//! Run with: zig run -O ReleaseFast benchmark.zig
//! Or for Debug mode: zig run benchmark.zig
//! JSON output: zig run -O ReleaseFast benchmark.zig -- --output json
//!
//! This benchmark measures the performance of:
//! - Tiger hash computation
//! - TigerTree hash computation at various sizes
//! - Base32 encoding/decoding

const std = @import("std");
const tth = @import("src/root.zig");
const time = std.time;
const builtin = @import("builtin");

const Timer = time.Timer;

const OutputFormat = enum {
    human,
    json,
};

/// Benchmark configuration
const Config = struct {
    /// Size multiplier for Debug mode (smaller datasets for faster feedback)
    const debug_scale = if (builtin.mode == .Debug) 64 else 1;

    /// Block size for hash benchmarks
    const block_size = 8192;

    /// Iterations for small operations
    const small_iterations = 10000 / debug_scale;

    /// Iterations for encoding/decoding
    const encode_iterations = 100000 / debug_scale;

    /// Number of benchmark runs to average
    const num_runs = 100;
};

/// Format throughput in human-readable form
fn printThroughput(bytes_per_sec: u64) void {
    if (bytes_per_sec >= 1024 * 1024 * 1024) {
        const gib_per_sec = @as(f64, @floatFromInt(bytes_per_sec)) / (1024.0 * 1024.0 * 1024.0);
        std.debug.print("{d:>8.2} GiB/s", .{gib_per_sec});
    } else if (bytes_per_sec >= 1024 * 1024) {
        const mib_per_sec = @as(f64, @floatFromInt(bytes_per_sec)) / (1024.0 * 1024.0);
        std.debug.print("{d:>8.2} MiB/s", .{mib_per_sec});
    } else if (bytes_per_sec >= 1024) {
        const kib_per_sec = @as(f64, @floatFromInt(bytes_per_sec)) / 1024.0;
        std.debug.print("{d:>8.2} KiB/s", .{kib_per_sec});
    } else {
        std.debug.print("{d:>8} B/s  ", .{bytes_per_sec});
    }
}

/// Format operations per second
fn printOpsPerSec(ops_per_sec: u64) void {
    if (ops_per_sec >= 1_000_000) {
        const m_ops = @as(f64, @floatFromInt(ops_per_sec)) / 1_000_000.0;
        std.debug.print("{d:>8.2} Mop/s", .{m_ops});
    } else if (ops_per_sec >= 1_000) {
        const k_ops = @as(f64, @floatFromInt(ops_per_sec)) / 1_000.0;
        std.debug.print("{d:>8.2} Kop/s", .{k_ops});
    } else {
        std.debug.print("{d:>8} op/s ", .{ops_per_sec});
    }
}

/// Benchmark Tiger hash at a specific size
fn benchmarkTiger(bytes: usize) !u64 {
    const blocks_count = bytes / Config.block_size;
    var block: [Config.block_size]u8 = undefined;

    // Pseudo-random test data
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    random.bytes(&block);

    var total_throughput: u64 = 0;

    // Average across multiple runs
    var run: usize = 0;
    while (run < Config.num_runs) : (run += 1) {
        var h = tth.Tiger.init(.{});

        var timer = try Timer.start();
        const start = timer.lap();

        var i: usize = 0;
        while (i < blocks_count) : (i += 1) {
            h.update(&block);
        }

        var final: [tth.digest_length]u8 = undefined;
        h.final(&final);
        std.mem.doNotOptimizeAway(final);

        const end = timer.read();

        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
        const throughput = @as(u64, @intFromFloat(@as(f64, @floatFromInt(bytes)) / elapsed_s));
        total_throughput += throughput;
    }

    return total_throughput / Config.num_runs;
}

/// Benchmark TigerTree hash at a specific size
fn benchmarkTigerTree(bytes: usize) !u64 {
    const blocks_count = bytes / Config.block_size;
    var block: [Config.block_size]u8 = undefined;

    // Pseudo-random test data
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    random.bytes(&block);

    var total_throughput: u64 = 0;

    // Average across multiple runs
    var run: usize = 0;
    while (run < Config.num_runs) : (run += 1) {
        var tree = tth.TigerTree.init(.{});

        var timer = try Timer.start();
        const start = timer.lap();

        var i: usize = 0;
        while (i < blocks_count) : (i += 1) {
            tree.update(&block);
        }

        var final: [24]u8 = undefined;
        tree.final(&final);
        std.mem.doNotOptimizeAway(final);

        const end = timer.read();

        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
        const throughput = @as(u64, @intFromFloat(@as(f64, @floatFromInt(bytes)) / elapsed_s));
        total_throughput += throughput;
    }

    return total_throughput / Config.num_runs;
}

/// Benchmark Base32 encoding
fn benchmarkBase32Encode() !u64 {
    const data = [_]u8{0x42} ** 24; // TTH hash size

    var total_ops: u64 = 0;

    // Average across multiple runs
    var run: usize = 0;
    while (run < Config.num_runs) : (run += 1) {
        var timer = try Timer.start();
        const start = timer.lap();

        var i: usize = 0;
        while (i < Config.encode_iterations) : (i += 1) {
            var buf: [39]u8 = undefined; // 24 bytes -> 39 base32 chars
            const encoded = tth.base32.standard_no_pad.Encoder.encode(&buf, &data);
            std.mem.doNotOptimizeAway(encoded);
        }

        const end = timer.read();

        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
        const ops_per_sec = @as(u64, @intFromFloat(@as(f64, @floatFromInt(Config.encode_iterations)) / elapsed_s));
        total_ops += ops_per_sec;
    }

    return total_ops / Config.num_runs;
}

/// Benchmark Base32 decoding
fn benchmarkBase32Decode() !u64 {
    const encoded = "LWPNACQDBZRYXW3VHJVCJ64QBZNGHOHHHZWCLNQ"; // 39 chars

    var total_ops: u64 = 0;

    // Average across multiple runs
    var run: usize = 0;
    while (run < Config.num_runs) : (run += 1) {
        var timer = try Timer.start();
        const start = timer.lap();

        var i: usize = 0;
        while (i < Config.encode_iterations) : (i += 1) {
            var buf: [24]u8 = undefined; // 39 base32 chars -> 24 bytes
            tth.base32.standard_no_pad.Decoder.decode(&buf, encoded) catch unreachable;
            std.mem.doNotOptimizeAway(buf);
        }

        const end = timer.read();

        const elapsed_s = @as(f64, @floatFromInt(end - start)) / time.ns_per_s;
        const ops_per_sec = @as(u64, @intFromFloat(@as(f64, @floatFromInt(Config.encode_iterations)) / elapsed_s));
        total_ops += ops_per_sec;
    }

    return total_ops / Config.num_runs;
}

const BenchmarkResults = struct {
    tiger: []ThroughputResult,
    tiger_tree: []ThroughputResult,
    base32_encode_ops: u64,
    base32_decode_ops: u64,
};

const ThroughputResult = struct {
    name: []const u8,
    size_bytes: usize,
    throughput_bytes_per_sec: u64,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var output_format = OutputFormat.human;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--output")) {
            continue;
        } else if (std.mem.eql(u8, arg, "json")) {
            output_format = .json;
        }
    }

    if (output_format == .human) {
        std.debug.print("\n", .{});
        std.debug.print("TTH Benchmark Suite\n", .{});
        std.debug.print("===================\n", .{});
        std.debug.print("Build mode: {s}\n", .{@tagName(builtin.mode)});
        std.debug.print("\n", .{});
        std.debug.print("Tiger Hash Throughput:\n", .{});
        std.debug.print("----------------------\n", .{});
    }

    const tiger_sizes = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 8 * 1024, .name = "8 KiB  " },
        .{ .size = 64 * 1024, .name = "64 KiB " },
        .{ .size = 512 * 1024, .name = "512 KiB" },
        .{ .size = 1024 * 1024, .name = "1 MiB  " },
        .{ .size = 8 * 1024 * 1024 / Config.debug_scale, .name = "8 MiB  " },
    };

    var tiger_results = std.ArrayList(ThroughputResult){};

    for (tiger_sizes) |size| {
        const throughput = try benchmarkTiger(size.size);
        try tiger_results.append(allocator, .{
            .name = size.name,
            .size_bytes = size.size,
            .throughput_bytes_per_sec = throughput,
        });

        if (output_format == .human) {
            std.debug.print("  {s}: ", .{size.name});
            printThroughput(throughput);
            std.debug.print("\n", .{});
        }
    }

    if (output_format == .human) {
        std.debug.print("\n", .{});
        std.debug.print("TigerTree Hash Throughput:\n", .{});
        std.debug.print("--------------------------\n", .{});
    }

    const tree_sizes = [_]struct { size: usize, name: []const u8 }{
        .{ .size = 8 * 1024, .name = "8 KiB  " },
        .{ .size = 64 * 1024, .name = "64 KiB " },
        .{ .size = 512 * 1024, .name = "512 KiB" },
        .{ .size = 1024 * 1024, .name = "1 MiB  " },
        .{ .size = 8 * 1024 * 1024 / Config.debug_scale, .name = "8 MiB  " },
    };

    var tree_results = std.ArrayList(ThroughputResult){};

    for (tree_sizes) |size| {
        const throughput = try benchmarkTigerTree(size.size);
        try tree_results.append(allocator, .{
            .name = size.name,
            .size_bytes = size.size,
            .throughput_bytes_per_sec = throughput,
        });

        if (output_format == .human) {
            std.debug.print("  {s}: ", .{size.name});
            printThroughput(throughput);
            std.debug.print("\n", .{});
        }
    }

    if (output_format == .human) {
        std.debug.print("\n", .{});
        std.debug.print("Base32 Performance:\n", .{});
        std.debug.print("-------------------\n", .{});
    }

    const encode_ops = try benchmarkBase32Encode();
    const decode_ops = try benchmarkBase32Decode();

    if (output_format == .human) {
        std.debug.print("  Encode: ", .{});
        printOpsPerSec(encode_ops);
        std.debug.print("\n", .{});

        std.debug.print("  Decode: ", .{});
        printOpsPerSec(decode_ops);
        std.debug.print("\n", .{});
        std.debug.print("\n", .{});
    } else {
        // JSON output - manually construct for simplicity
        std.debug.print("{{\n", .{});
        std.debug.print("  \"tiger\": [\n", .{});
        for (tiger_results.items, 0..) |result, i| {
            std.debug.print("    {{\n", .{});
            std.debug.print("      \"name\": \"{s}\",\n", .{result.name});
            std.debug.print("      \"size_bytes\": {d},\n", .{result.size_bytes});
            std.debug.print("      \"throughput_bytes_per_sec\": {d}\n", .{result.throughput_bytes_per_sec});
            if (i < tiger_results.items.len - 1) {
                std.debug.print("    }},\n", .{});
            } else {
                std.debug.print("    }}\n", .{});
            }
        }
        std.debug.print("  ],\n", .{});

        std.debug.print("  \"tiger_tree\": [\n", .{});
        for (tree_results.items, 0..) |result, i| {
            std.debug.print("    {{\n", .{});
            std.debug.print("      \"name\": \"{s}\",\n", .{result.name});
            std.debug.print("      \"size_bytes\": {d},\n", .{result.size_bytes});
            std.debug.print("      \"throughput_bytes_per_sec\": {d}\n", .{result.throughput_bytes_per_sec});
            if (i < tree_results.items.len - 1) {
                std.debug.print("    }},\n", .{});
            } else {
                std.debug.print("    }}\n", .{});
            }
        }
        std.debug.print("  ],\n", .{});

        std.debug.print("  \"base32_encode_ops\": {d},\n", .{encode_ops});
        std.debug.print("  \"base32_decode_ops\": {d}\n", .{decode_ops});
        std.debug.print("}}\n", .{});
    }
}
