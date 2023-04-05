const std = @import("std");
const fmtDuration = std.fmt.fmtDuration;
const print = std.debug.print;
const math = std.math;
//usingnamespace @import("haversine_tests.zig");

comptime {
    @setFloatMode(.Optimized);
}

// All tests / benchmarks done on:
//
//      CPU: (Skylake) Intel i7-6700 CPU @ 3.40GHz
//              turbo boost up to 4Ghz
//              4 cores / 8 threads
//              Cache L1: 	64K (per core)
//              Cache L2: 	256K (per core)
//              Cache L3: 	8MB (shared)
//      RAM: 32GB dual-channel (Crucial CT16G4DFRA266  2 x 16 GB DDR4 2666 MHz)
//      OS:  Windows 10 pro x64 (installed on SSD)
//      With program and test data placed on HDD (should not matter that much (for non generator part) as input file should be cached by OS)

/// switch between f32 vs f64 to see performance impact
///     processing time is faster, but with parsing taking most of total time
/// you can try f16, f80 or f128 as well, however at time of writing zig standard library didn't support most of the math functions needed
const Float = f64;

/// set to 0 to disable buffering and see impact when generating test-data
/// on my PC with HDD, buffering improves write performance ~ 40X
/// buffer size doesn't matter that much as long as its not too small. Size around few pages seems to be optimal.
/// my results were:
///    | buffer size (bytes)    | time to generate & write 1 million pairs |
///    +------------------------+------------------------------------------+
///    | 0 (buffering disabled) |  40   sec
///    | 16                     |  18   sec
///    | 128                    |  3    sec
///    | 512                    |  1.6  sec
///    | page_size * 1   (4KiB) |  1.17 sec
///    | page_size * 4          |  0.99 sec
///    | page_size * 8          |  0.96 sec
///    | page_size * 16         |  0.94 sec  <-- around this level it is difficult to distinguish time differences and variance might be measurement error
///    | page_size * 32         |  0.99 sec
///    | page_size * 128        |  0.92 sec
const gen_write_buffer_size = std.mem.page_size * 16;

/// When set to true allows parsing json files that have additional data within them. Otherwise parsing will report error.
const json_ignore_unknown_fields = true;

/// simple toggle to print each test iteration result
/// somehow disabling it creates suspiciously low math timings (most likely compiler inlines and moves stuff around too much)
const print_each_test_iteration = true;

/// enter radius used for haversine
// TODO: might be that constant gets optimized slightly more, it might be more fair to read it as argument
const earth_radius = 6371;

/// Generate random test file with pairs of coordinates
pub fn gen(absolute_path: []const u8, pair_count: usize) !void {
    var timer = try std.time.Timer.start();

    const file = try std.fs.createFileAbsolute(absolute_path, .{ .truncate = true });
    defer file.close();

    var unbuffered_writer = file.writer();
    var buffered_writer = std.io.BufferedWriter(gen_write_buffer_size, @TypeOf(unbuffered_writer)){ .unbuffered_writer = unbuffered_writer };
    var writer = if (gen_write_buffer_size > 0) buffered_writer.writer() else unbuffered_writer;

    try writer.writeAll("{\"pairs\":[\n");

    const seed = 12345;
    var rand_gen = std.rand.DefaultPrng.init(seed);
    var rand = rand_gen.random();
    var i: usize = 1;
    if (pair_count > 0) {
        // fixed precision
        //const format: []const u8 = "{{\"x0\":{d:.5},\"y0\":{d:.5},\"x1\":{d:.5},\"y1\":{d:.5}}}";
        // full precision
        const format: []const u8 = "{{\"x0\":{},\"y0\":{},\"x1\":{},\"y1\":{}}}";
        while (i < pair_count) : (i += 1) {
            try writer.print(format ++ ",\n", .{
                rand.float(Float) * 360 - 180,
                rand.float(Float) * 360 - 180,
                rand.float(Float) * 360 - 180,
                rand.float(Float) * 360 - 180,
            });
        }
        // tail row without ',' at end
        try writer.print(format ++ "\n", .{
            rand.float(Float) * 360 - 180,
            rand.float(Float) * 360 - 180,
            rand.float(Float) * 360 - 180,
            rand.float(Float) * 360 - 180,
        });
    }
    try writer.writeAll("]}");

    // IMPORTANT: can't be skipped: file.close doesn't know about buffering - must be flushed manually
    // unfortunately, defer can't be used because defer can't return errors
    try buffered_writer.flush();

    print("gen done and written in {}\n", .{fmtDuration(timer.read())});
}

inline fn sqr(x: Float) Float {
    return x * x;
}

pub inline fn haversineDistance(x0_deg: Float, y0_deg: Float, x1_deg: Float, y1_deg: Float, radius: Float) Float {
    const dY = math.degreesToRadians(Float, y1_deg - y0_deg);
    const dX = math.degreesToRadians(Float, x1_deg - x0_deg);
    const y0 = math.degreesToRadians(Float, y0_deg);
    const y1 = math.degreesToRadians(Float, y1_deg);

    var root = (sqr(math.sin(dY / 2.0))) + math.cos(y0) * math.cos(y1) * sqr(math.sin(dX / 2));
    return 2.0 * radius * math.asin(math.sqrt(root));
}

pub fn processFile(absolute_path: []const u8) !Result {
    var timer = try std.time.Timer.start();
    const alloc = heap_alloc;

    // read
    const file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();

    const input_data = try file.readToEndAlloc(alloc, math.maxInt(usize));
    defer alloc.free(input_data);
    const read_time = timer.lap();

    // parse
    var stream = std.json.TokenStream.init(input_data);
    const Template = struct {
        pairs: []Pair,
    };
    const options = .{ .allocator = alloc, .ignore_unknown_fields = json_ignore_unknown_fields };
    const result = try std.json.parse(Template, &stream, options);
    defer std.json.parseFree(Template, result, options);
    const parse_time = timer.lap();

    // math
    var sum: Float = 0;
    for (result.pairs) |p| {
        sum += haversineDistance(p.x0, p.y0, p.x1, p.y1, earth_radius);
    }

    const math_time = timer.read();

    return .{ .count = result.pairs.len, .sum = sum, .parse_time = parse_time, .math_time = math_time, .read_time = read_time };
}

pub fn main() !void {
    var exe_path_buff: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const exe_path = try std.fs.selfExeDirPath(&exe_path_buff);
    var test_path = try std.fs.path.join(heap_alloc, &.{ exe_path, "test.json" });
    defer heap_alloc.free(test_path);

    // Argument parsing & testing harness
    const args = try std.process.argsAlloc(heap_alloc);
    defer std.process.argsFree(heap_alloc, args);
    var ai: usize = 0;
    while (ai < args.len) : (ai += 1) {
        if (std.ascii.eqlIgnoreCase(args[ai], "-g")) {
            // GENERATE
            ai += 1;
            if (ai < args.len) {
                var n = std.fmt.parseInt(usize, args[ai], 10) catch |err| {
                    print("Argument '-n' expects integer after it, parse error: {}\n", .{err});
                    return;
                };
                gen(test_path, n) catch |err| {
                    print("error {} generating file '{s}'\n", .{err, test_path});
                    return err;
                };
            } else {
                print("Argument '-n' expects integer after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-f")) {
            // SET FILE
            ai += 1;
            if (ai < args.len) {
                heap_alloc.free(test_path);
                test_path = if (std.fs.path.isAbsolute(args[ai])) try heap_alloc.dupe(u8, args[ai]) else try std.fs.path.join(heap_alloc, &.{ exe_path, args[ai] });
            } else {
                print("Argument '-f' expects file name after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-r")) {
            // RUN
            var i: i32 = 0;
            while (i < total_iterations) : (i += 1) {
                var timer = try std.time.Timer.start();
                var res = try processFile(test_path);
                res.total_time = timer.read();

                if (print_each_test_iteration) {
                    print("-" ** 80 ++ "\n", .{});
                    print("{}#\n", .{i});
                    print("\t" ++ "avg haversine:          {d:.5}\n", .{res.sum / @intToFloat(Float, res.count)});
                    print("\t" ++ "read time:               {}\n", .{fmtDuration(res.read_time)});
                    print("\t" ++ "parse time:              {}\n", .{fmtDuration(res.parse_time)});
                    print("\t" ++ "math time:               {}\n", .{fmtDuration(res.math_time)});
                    print("\t" ++ "total time:              {}\n", .{fmtDuration(res.total_time)});
                    print("\t" ++ "throughput:              {} haversines/second\n", .{res.count * std.time.ns_per_s / res.total_time});
                }

                total_res.read_time = math.min(total_res.read_time, res.read_time);
                total_res.parse_time = math.min(total_res.parse_time, res.parse_time);
                total_res.math_time = math.min(total_res.math_time, res.math_time);
                total_res.total_time = math.min(total_res.total_time, res.total_time);

                total_res.count = res.count;
                total_res.sum = res.sum;
            }
            //if (i > 1 or !print_each_test_iteration)
            {
                const res = total_res;
                print("=" ** 80 ++ "\nBEST SUB-RESULTS:\n", .{});
                print("(test-iterations: {}, input size: {}, float: {})\n", .{ total_iterations, res.count, Float });
                print("\t" ++ "avg haversine:          {d:.5}\n", .{res.sum / @intToFloat(Float, res.count)});
                print("\t" ++ "read time:               {}\n", .{fmtDuration(res.read_time)});
                print("\t" ++ "parse time:              {}\n", .{fmtDuration(res.parse_time)});
                print("\t" ++ "math time:               {}\n", .{fmtDuration(res.math_time)});
                print("\t" ++ "total time:              {}\n", .{fmtDuration(res.total_time)});
                print("\t" ++ "throughput:              {} haversines/second\n", .{res.count * std.time.ns_per_s / res.total_time});
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-i")) {
            // SET ITERATIONS
            ai += 1;
            if (ai < args.len) {
                total_iterations = std.fmt.parseInt(usize, args[ai], 10) catch |err| {
                    print("Argument '-i' expects integer after it, parse error: {}\n", .{err});
                    return;
                };
            } else {
                print("Argument '-i' expects integer after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-h") or std.ascii.eqlIgnoreCase(args[ai], "--help")) {
            // HELP
            print("Help: \n  Runs commands in order possible commands: \n", .{});
            print("\t-f X \t\t switch json in/out file to file named X\n", .{});
            print("\t-g X \t\t generates json file (previously specified with -f) with X pairs\n", .{});
            print("\t-i X \t\t set test/benchmarking iteration count\n", .{});
            print("\t-r X \t\t run the haversine processing\n", .{});
        }
    }
}

// runtime global variables and utils
var total_iterations: usize = 1;
var heap: std.heap.GeneralPurposeAllocator(.{}) = .{};
var heap_alloc = heap.allocator();
var total_res: Result = .{};
const Pair = struct { x0: Float, y0: Float, x1: Float, y1: Float };

const Result = struct {
    count: usize = 0,
    sum: Float = math.nan(Float),

    read_time: u64 = math.maxInt(u64),
    parse_time: u64 = math.maxInt(u64),
    math_time: u64 = math.maxInt(u64),
    total_time: u64 = math.maxInt(u64),
};
