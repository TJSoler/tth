//! Benchmark Comparison Tool with Statistical Analysis
//!
//! Compares multiple benchmark runs using Welch's t-test for statistical significance.
//!
//! Usage: zig run scripts/compare_benchmarks.zig -- \
//!   --main <main_1.json> <main_2.json> ... \
//!   --pr <pr_1.json> <pr_2.json> ... \
//!   --threshold <percent>
//!
//! Exit codes:
//!   0 - No regression or within threshold
//!   1 - Regression exceeds threshold
//!   2 - Usage error or file error

const std = @import("std");

const BenchmarkData = struct {
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

const Stats = struct {
    mean: f64,
    std_dev: f64,
    n: usize,
};

const RegressionInfo = struct {
    category: []const u8,
    name: []const u8,
    main_stats: Stats,
    pr_stats: Stats,
    change_percent: f64,
    p_value: f64,
};

fn loadBenchmarkData(allocator: std.mem.Allocator, file_path: []const u8) !std.json.Parsed(BenchmarkData) {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    return try std.json.parseFromSlice(BenchmarkData, allocator, content, .{});
}

/// Calculate mean, standard deviation, and count for a set of values
fn calculateStats(values: []const f64) Stats {
    if (values.len == 0) return .{ .mean = 0, .std_dev = 0, .n = 0 };
    if (values.len == 1) return .{ .mean = values[0], .std_dev = 0, .n = 1 };

    // Calculate mean
    var sum: f64 = 0;
    for (values) |v| {
        sum += v;
    }
    const mean = sum / @as(f64, @floatFromInt(values.len));

    // Calculate standard deviation
    var sum_squared_diff: f64 = 0;
    for (values) |v| {
        const diff = v - mean;
        sum_squared_diff += diff * diff;
    }
    const variance = sum_squared_diff / @as(f64, @floatFromInt(values.len - 1));
    const std_dev = @sqrt(variance);

    return .{
        .mean = mean,
        .std_dev = std_dev,
        .n = values.len,
    };
}

/// Remove outliers using IQR method
/// Returns a new slice with outliers removed (allocated with provided allocator)
fn removeOutliers(allocator: std.mem.Allocator, values: []const f64) ![]f64 {
    if (values.len < 4) {
        // Insufficient samples for outlier detection
        const result = try allocator.alloc(f64, values.len);
        @memcpy(result, values);
        return result;
    }

    // Create a sorted copy
    const sorted = try allocator.alloc(f64, values.len);
    @memcpy(sorted, values);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    defer allocator.free(sorted);

    // Calculate Q1, Q3, and IQR
    const q1_idx = values.len / 4;
    const q3_idx = (values.len * 3) / 4;
    const q1 = sorted[q1_idx];
    const q3 = sorted[q3_idx];
    const iqr = q3 - q1;

    const lower_bound = q1 - 1.5 * iqr;
    const upper_bound = q3 + 1.5 * iqr;

    // Filter outliers
    var filtered = std.ArrayList(f64){};
    defer filtered.deinit(allocator);

    for (values) |v| {
        if (v >= lower_bound and v <= upper_bound) {
            try filtered.append(allocator, v);
        }
    }

    // Ensure we have at least 3 samples after filtering
    if (filtered.items.len < 3) {
        // Fallback to original values when too few samples remain
        const result = try allocator.alloc(f64, values.len);
        @memcpy(result, values);
        return result;
    }

    return try filtered.toOwnedSlice(allocator);
}

/// Perform Welch's t-test and return p-value (two-tailed)
fn welchTTest(main_stats: Stats, pr_stats: Stats) f64 {
    if (main_stats.n == 0 or pr_stats.n == 0) return 1.0;
    if (main_stats.n == 1 and pr_stats.n == 1) return 1.0;

    // Calculate t-statistic
    const mean_diff = @abs(pr_stats.mean - main_stats.mean);
    const main_var = main_stats.std_dev * main_stats.std_dev;
    const pr_var = pr_stats.std_dev * pr_stats.std_dev;

    const main_n = @as(f64, @floatFromInt(main_stats.n));
    const pr_n = @as(f64, @floatFromInt(pr_stats.n));

    const se = @sqrt((main_var / main_n) + (pr_var / pr_n));
    if (se == 0) return 1.0; // No variance, can't determine significance

    const t = mean_diff / se;

    // Calculate degrees of freedom (Welch-Satterthwaite equation)
    const numerator = ((main_var / main_n) + (pr_var / pr_n)) * ((main_var / main_n) + (pr_var / pr_n));
    const denom1 = (main_var * main_var) / (main_n * main_n * (main_n - 1));
    const denom2 = (pr_var * pr_var) / (pr_n * pr_n * (pr_n - 1));
    const df = numerator / (denom1 + denom2);

    if (df < 1) return 1.0;

    // Conservative t-distribution approximation based on common critical values
    if (t > 4.0) return 0.001;
    if (t > 3.5) return 0.01;
    if (t > 2.5) return 0.05;
    if (t > 2.0) return 0.1;
    if (t > 1.5) return 0.2;
    return 0.5; // Not significant
}

fn calculateChangePercent(baseline: f64, current: f64) f64 {
    if (baseline == 0) return 0.0;
    return ((current - baseline) / baseline) * 100.0;
}

const ParsedArgs = struct {
    main_files: []const []const u8,
    pr_files: []const []const u8,
    threshold: f64,
};

fn parseArgs(allocator: std.mem.Allocator) !ParsedArgs {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // First pass: count files
    var main_count: usize = 0;
    var pr_count: usize = 0;
    var threshold: f64 = 10.0;

    var i: usize = 1;
    var counting_main = false;
    var counting_pr = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--main")) {
            counting_main = true;
            counting_pr = false;
        } else if (std.mem.eql(u8, arg, "--pr")) {
            counting_pr = true;
            counting_main = false;
        } else if (std.mem.eql(u8, arg, "--threshold")) {
            i += 1;
            if (i < args.len) {
                threshold = try std.fmt.parseFloat(f64, args[i]);
            }
            counting_main = false;
            counting_pr = false;
        } else if (counting_main) {
            main_count += 1;
        } else if (counting_pr) {
            pr_count += 1;
        }
    }

    if (main_count == 0 or pr_count == 0) {
        std.debug.print("Usage: compare_benchmarks --main <files...> --pr <files...> --threshold <percent>\n", .{});
        std.process.exit(2);
    }

    // Second pass: collect files
    const main_files = try allocator.alloc([]const u8, main_count);
    const pr_files = try allocator.alloc([]const u8, pr_count);

    i = 1;
    counting_main = false;
    counting_pr = false;
    var main_idx: usize = 0;
    var pr_idx: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--main")) {
            counting_main = true;
            counting_pr = false;
        } else if (std.mem.eql(u8, arg, "--pr")) {
            counting_pr = true;
            counting_main = false;
        } else if (std.mem.eql(u8, arg, "--threshold")) {
            i += 1; // Skip threshold value
            counting_main = false;
            counting_pr = false;
        } else if (counting_main) {
            main_files[main_idx] = try allocator.dupe(u8, arg);
            main_idx += 1;
        } else if (counting_pr) {
            pr_files[pr_idx] = try allocator.dupe(u8, arg);
            pr_idx += 1;
        }
    }

    return ParsedArgs{
        .main_files = main_files,
        .pr_files = pr_files,
        .threshold = threshold,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed_args = try parseArgs(allocator);
    defer allocator.free(parsed_args.main_files);
    defer allocator.free(parsed_args.pr_files);

    std.debug.print("Comparing benchmarks with statistical analysis:\n", .{});
    std.debug.print("  Main runs: {d}\n", .{parsed_args.main_files.len});
    std.debug.print("  PR runs:   {d}\n", .{parsed_args.pr_files.len});
    std.debug.print("  Threshold: {d:.1}%\n", .{parsed_args.threshold});
    std.debug.print("  Significance level: p < 0.05\n\n", .{});

    // Load all main benchmark files
    var main_samples = std.ArrayList(std.json.Parsed(BenchmarkData)){};
    defer {
        for (main_samples.items) |sample| {
            sample.deinit();
        }
        main_samples.deinit(allocator);
    }

    for (parsed_args.main_files) |file| {
        const data = loadBenchmarkData(allocator, file) catch |err| {
            std.debug.print("Error loading main file {s}: {}\n", .{ file, err });
            std.process.exit(2);
        };
        try main_samples.append(allocator, data);
    }

    // Load all PR benchmark files
    var pr_samples = std.ArrayList(std.json.Parsed(BenchmarkData)){};
    defer {
        for (pr_samples.items) |sample| {
            sample.deinit();
        }
        pr_samples.deinit(allocator);
    }

    for (parsed_args.pr_files) |file| {
        const data = loadBenchmarkData(allocator, file) catch |err| {
            std.debug.print("Error loading PR file {s}: {}\n", .{ file, err });
            std.process.exit(2);
        };
        try pr_samples.append(allocator, data);
    }

    var regressions = std.ArrayList(RegressionInfo){};
    defer regressions.deinit(allocator);

    // Compare Tiger benchmarks
    std.debug.print("Tiger Hash Benchmarks:\n", .{});
    std.debug.print("{s}\n", .{"-" ** 80});

    // Use minimum length to handle format transitions between benchmark versions
    const main_tiger_len = main_samples.items[0].value.tiger.len;
    const pr_tiger_len = pr_samples.items[0].value.tiger.len;
    const num_tiger = @min(main_tiger_len, pr_tiger_len);
    if (main_tiger_len != pr_tiger_len) {
        std.debug.print("  Note: Different benchmark sizes (main={d}, pr={d}), comparing {d} common entries\n\n", .{ main_tiger_len, pr_tiger_len, num_tiger });
    }
    var bench_idx: usize = 0;
    while (bench_idx < num_tiger) : (bench_idx += 1) {
        // Collect all samples for this benchmark
        var main_values = std.ArrayList(f64){};
        defer main_values.deinit(allocator);
        var pr_values = std.ArrayList(f64){};
        defer pr_values.deinit(allocator);

        for (main_samples.items) |sample| {
            const throughput = @as(f64, @floatFromInt(sample.value.tiger[bench_idx].throughput_bytes_per_sec));
            try main_values.append(allocator, throughput);
        }

        for (pr_samples.items) |sample| {
            const throughput = @as(f64, @floatFromInt(sample.value.tiger[bench_idx].throughput_bytes_per_sec));
            try pr_values.append(allocator, throughput);
        }

        // Remove outliers
        const main_filtered = try removeOutliers(allocator, main_values.items);
        defer allocator.free(main_filtered);
        const pr_filtered = try removeOutliers(allocator, pr_values.items);
        defer allocator.free(pr_filtered);

        // Calculate statistics
        const main_stats = calculateStats(main_filtered);
        const pr_stats = calculateStats(pr_filtered);

        const change = calculateChangePercent(main_stats.mean, pr_stats.mean);
        const p_value = welchTTest(main_stats, pr_stats);

        const size_bytes = main_samples.items[0].value.tiger[bench_idx].size_bytes;
        std.debug.print("  Size {d} bytes:\n", .{size_bytes});
        std.debug.print("    Main: {d:.2} MB/s ± {d:.2} MB/s (n={d})\n", .{
            main_stats.mean / (1024.0 * 1024.0),
            main_stats.std_dev / (1024.0 * 1024.0),
            main_stats.n,
        });
        std.debug.print("    PR:   {d:.2} MB/s ± {d:.2} MB/s (n={d})\n", .{
            pr_stats.mean / (1024.0 * 1024.0),
            pr_stats.std_dev / (1024.0 * 1024.0),
            pr_stats.n,
        });
        std.debug.print("    Change: {d:.2}% (p={d:.3})", .{ change, p_value });

        // Check for regression
        const is_statistically_significant = p_value < 0.05;
        const is_practically_significant = change < -parsed_args.threshold;

        if (is_statistically_significant and is_practically_significant) {
            std.debug.print(" ⚠️  REGRESSION\n\n", .{});
            const name_buf = try std.fmt.allocPrint(allocator, "{d} bytes", .{size_bytes});
            try regressions.append(allocator, .{
                .category = "Tiger",
                .name = name_buf,
                .main_stats = main_stats,
                .pr_stats = pr_stats,
                .change_percent = change,
                .p_value = p_value,
            });
        } else if (is_practically_significant) {
            std.debug.print(" (not statistically significant)\n\n", .{});
        } else {
            std.debug.print(" ✓\n\n", .{});
        }
    }

    // Compare TigerTree benchmarks
    std.debug.print("TigerTree Hash Benchmarks:\n", .{});
    std.debug.print("{s}\n", .{"-" ** 80});

    // Use minimum length to handle format transitions between benchmark versions
    const main_tree_len = main_samples.items[0].value.tiger_tree.len;
    const pr_tree_len = pr_samples.items[0].value.tiger_tree.len;
    const num_tree = @min(main_tree_len, pr_tree_len);
    if (main_tree_len != pr_tree_len) {
        std.debug.print("  Note: Different benchmark sizes (main={d}, pr={d}), comparing {d} common entries\n\n", .{ main_tree_len, pr_tree_len, num_tree });
    }
    bench_idx = 0;
    while (bench_idx < num_tree) : (bench_idx += 1) {
        var main_values = std.ArrayList(f64){};
        defer main_values.deinit(allocator);
        var pr_values = std.ArrayList(f64){};
        defer pr_values.deinit(allocator);

        for (main_samples.items) |sample| {
            const throughput = @as(f64, @floatFromInt(sample.value.tiger_tree[bench_idx].throughput_bytes_per_sec));
            try main_values.append(allocator, throughput);
        }

        for (pr_samples.items) |sample| {
            const throughput = @as(f64, @floatFromInt(sample.value.tiger_tree[bench_idx].throughput_bytes_per_sec));
            try pr_values.append(allocator, throughput);
        }

        const main_filtered = try removeOutliers(allocator, main_values.items);
        defer allocator.free(main_filtered);
        const pr_filtered = try removeOutliers(allocator, pr_values.items);
        defer allocator.free(pr_filtered);

        const main_stats = calculateStats(main_filtered);
        const pr_stats = calculateStats(pr_filtered);

        const change = calculateChangePercent(main_stats.mean, pr_stats.mean);
        const p_value = welchTTest(main_stats, pr_stats);

        const size_bytes = main_samples.items[0].value.tiger_tree[bench_idx].size_bytes;
        std.debug.print("  Size {d} bytes:\n", .{size_bytes});
        std.debug.print("    Main: {d:.2} MB/s ± {d:.2} MB/s (n={d})\n", .{
            main_stats.mean / (1024.0 * 1024.0),
            main_stats.std_dev / (1024.0 * 1024.0),
            main_stats.n,
        });
        std.debug.print("    PR:   {d:.2} MB/s ± {d:.2} MB/s (n={d})\n", .{
            pr_stats.mean / (1024.0 * 1024.0),
            pr_stats.std_dev / (1024.0 * 1024.0),
            pr_stats.n,
        });
        std.debug.print("    Change: {d:.2}% (p={d:.3})", .{ change, p_value });

        const is_statistically_significant = p_value < 0.05;
        const is_practically_significant = change < -parsed_args.threshold;

        if (is_statistically_significant and is_practically_significant) {
            std.debug.print(" ⚠️  REGRESSION\n\n", .{});
            const name_buf = try std.fmt.allocPrint(allocator, "{d} bytes", .{size_bytes});
            try regressions.append(allocator, .{
                .category = "TigerTree",
                .name = name_buf,
                .main_stats = main_stats,
                .pr_stats = pr_stats,
                .change_percent = change,
                .p_value = p_value,
            });
        } else if (is_practically_significant) {
            std.debug.print(" (not statistically significant)\n\n", .{});
        } else {
            std.debug.print(" ✓\n\n", .{});
        }
    }

    // Compare Base32 encode
    std.debug.print("Base32 Encode Benchmark:\n", .{});
    std.debug.print("{s}\n", .{"-" ** 80});
    {
        var main_values = std.ArrayList(f64){};
        defer main_values.deinit(allocator);
        var pr_values = std.ArrayList(f64){};
        defer pr_values.deinit(allocator);

        for (main_samples.items) |sample| {
            const ops = @as(f64, @floatFromInt(sample.value.base32_encode_ops));
            try main_values.append(allocator, ops);
        }

        for (pr_samples.items) |sample| {
            const ops = @as(f64, @floatFromInt(sample.value.base32_encode_ops));
            try pr_values.append(allocator, ops);
        }

        const main_filtered = try removeOutliers(allocator, main_values.items);
        defer allocator.free(main_filtered);
        const pr_filtered = try removeOutliers(allocator, pr_values.items);
        defer allocator.free(pr_filtered);

        const main_stats = calculateStats(main_filtered);
        const pr_stats = calculateStats(pr_filtered);

        const change = calculateChangePercent(main_stats.mean, pr_stats.mean);
        const p_value = welchTTest(main_stats, pr_stats);

        std.debug.print("  Main: {d:.2} Kop/s ± {d:.2} Kop/s (n={d})\n", .{
            main_stats.mean / 1000.0,
            main_stats.std_dev / 1000.0,
            main_stats.n,
        });
        std.debug.print("  PR:   {d:.2} Kop/s ± {d:.2} Kop/s (n={d})\n", .{
            pr_stats.mean / 1000.0,
            pr_stats.std_dev / 1000.0,
            pr_stats.n,
        });
        std.debug.print("  Change: {d:.2}% (p={d:.3})", .{ change, p_value });

        const is_statistically_significant = p_value < 0.05;
        const is_practically_significant = change < -parsed_args.threshold;

        if (is_statistically_significant and is_practically_significant) {
            std.debug.print(" ⚠️  REGRESSION\n\n", .{});
            try regressions.append(allocator, .{
                .category = "Base32",
                .name = "Encode",
                .main_stats = main_stats,
                .pr_stats = pr_stats,
                .change_percent = change,
                .p_value = p_value,
            });
        } else if (is_practically_significant) {
            std.debug.print(" (not statistically significant)\n\n", .{});
        } else {
            std.debug.print(" ✓\n\n", .{});
        }
    }

    // Compare Base32 decode
    std.debug.print("Base32 Decode Benchmark:\n", .{});
    std.debug.print("{s}\n", .{"-" ** 80});
    {
        var main_values = std.ArrayList(f64){};
        defer main_values.deinit(allocator);
        var pr_values = std.ArrayList(f64){};
        defer pr_values.deinit(allocator);

        for (main_samples.items) |sample| {
            const ops = @as(f64, @floatFromInt(sample.value.base32_decode_ops));
            try main_values.append(allocator, ops);
        }

        for (pr_samples.items) |sample| {
            const ops = @as(f64, @floatFromInt(sample.value.base32_decode_ops));
            try pr_values.append(allocator, ops);
        }

        const main_filtered = try removeOutliers(allocator, main_values.items);
        defer allocator.free(main_filtered);
        const pr_filtered = try removeOutliers(allocator, pr_values.items);
        defer allocator.free(pr_filtered);

        const main_stats = calculateStats(main_filtered);
        const pr_stats = calculateStats(pr_filtered);

        const change = calculateChangePercent(main_stats.mean, pr_stats.mean);
        const p_value = welchTTest(main_stats, pr_stats);

        std.debug.print("  Main: {d:.2} Kop/s ± {d:.2} Kop/s (n={d})\n", .{
            main_stats.mean / 1000.0,
            main_stats.std_dev / 1000.0,
            main_stats.n,
        });
        std.debug.print("  PR:   {d:.2} Kop/s ± {d:.2} Kop/s (n={d})\n", .{
            pr_stats.mean / 1000.0,
            pr_stats.std_dev / 1000.0,
            pr_stats.n,
        });
        std.debug.print("  Change: {d:.2}% (p={d:.3})", .{ change, p_value });

        const is_statistically_significant = p_value < 0.05;
        const is_practically_significant = change < -parsed_args.threshold;

        if (is_statistically_significant and is_practically_significant) {
            std.debug.print(" ⚠️  REGRESSION\n\n", .{});
            try regressions.append(allocator, .{
                .category = "Base32",
                .name = "Decode",
                .main_stats = main_stats,
                .pr_stats = pr_stats,
                .change_percent = change,
                .p_value = p_value,
            });
        } else if (is_practically_significant) {
            std.debug.print(" (not statistically significant)\n\n", .{});
        } else {
            std.debug.print(" ✓\n\n", .{});
        }
    }

    // Final verdict
    if (regressions.items.len > 0) {
        std.debug.print("❌ PERFORMANCE REGRESSION DETECTED:\n", .{});
        std.debug.print("{s}\n", .{"=" ** 80});
        std.debug.print("The following benchmarks show statistically significant regressions\n", .{});
        std.debug.print("exceeding the {d:.1}% threshold:\n\n", .{parsed_args.threshold});

        for (regressions.items) |reg| {
            std.debug.print("{s} - {s}:\n", .{ reg.category, reg.name });
            std.debug.print("  Main:   {d:.2} (±{d:.2})\n", .{ reg.main_stats.mean, reg.main_stats.std_dev });
            std.debug.print("  PR:     {d:.2} (±{d:.2})\n", .{ reg.pr_stats.mean, reg.pr_stats.std_dev });
            std.debug.print("  Change: {d:.2}%\n", .{reg.change_percent});
            std.debug.print("  p-value: {d:.3} (< 0.05 = significant)\n\n", .{reg.p_value});
        }
        std.process.exit(1);
    } else {
        std.debug.print("✅ No statistically significant performance regressions detected.\n", .{});
        std.process.exit(0);
    }
}
