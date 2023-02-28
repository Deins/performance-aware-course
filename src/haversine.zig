const std = @import("std");
const fmtDuration = std.fmt.fmtDuration;
const print = std.debug.print;

// All tests / benchmarks done on:
//      CPU: Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz
//              turbo boost up to 4Ghz
//              4 cores / 8 threads
//              Cache L1: 	64K (per core)
//              Cache L2: 	256K (per core)
//              Cache L3: 	8MB (shared)
//      RAM: 32GB (Crucial CT16G4DFRA266  2 x 16 GB DDR4 2666 MHz)
//      OS:  Windows 10 pro x64 (installed on SSD)
//      With program and test data placed on HDD (not sure how much it matters test (non generator part) as input file should be cached by OS)

/// switch between f32 vs f64 to see performance impact
///     processing time is slightly faster, but with parsing taking most of it total time differs little
/// you can try f16, f80 or f128 as well, however at time of writing zig standard library didn't support most of the math functions needed
const Float = f32;

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
/// Doesn't seem to have much of an performance impact (when tested on data without extra fields)
const json_ignore_unknown_fields = true;

/// simple toggle to print each test iterations result
const print_each_test_iteration = true;

/// enter radius used for harvesine
// TODO: might be that constant gets optimized slightly more, it might be more fair to read it as argument
const earth_radius = 6371.0;

/// Generate test file with pairs of coordinates
pub fn gen(absolute_path: []const u8, pair_count: usize) !void {
    var timer = try std.time.Timer.start();

    const file = try std.fs.createFileAbsolute(absolute_path, .{ .truncate = true });
    defer file.close();

    var unbuffered_writer = file.writer();
    var buffered_writer = std.io.BufferedWriter(gen_write_buffer_size, @TypeOf(unbuffered_writer)){ .unbuffered_writer = unbuffered_writer };
    var writer = if (gen_write_buffer_size > 0) buffered_writer.writer() else unbuffered_writer;

    try writer.writeAll("{\"pairs\":[\n");

    const seed = 12345;
    var rand = std.rand.DefaultPrng.init(seed);
    var i: usize = 1;
    if (pair_count > 0) {
        const format: []const u8 = "{{\"x0\":{d:.5},\"y0\":{d:.5},\"x1\":{d:.5},\"y1\":{d:.5}}}";
        while (i < pair_count) : (i += 1) {
            try writer.print(format ++ ",\n", .{
                rand.random().float(Float) * 360 - 180,
                rand.random().float(Float) * 360 - 180,
                rand.random().float(Float) * 360 - 180,
                rand.random().float(Float) * 360 - 180,
            });
        }
        // tail row without ',' at end
        try writer.print(format ++ "\n", .{
            rand.random().float(Float) * 360 - 180,
            rand.random().float(Float) * 360 - 180,
            rand.random().float(Float) * 360 - 180,
            rand.random().float(Float) * 360 - 180,
        });
    }

    try writer.writeAll("]}");

    try buffered_writer.flush();

    print("gen done in {}\n", .{fmtDuration(timer.read())});
}

pub inline fn radians(degrees: Float) Float {
    return degrees * (std.math.pi / 180.0);
}

inline fn sqr(x: Float) Float {
    return x * x;
}

pub inline fn haversineDistance(x0_deg: Float, y0_deg: Float, x1_deg: Float, y1_deg: Float, radius: Float) Float {
    const dY = radians(y1_deg - y0_deg);
    const dX = radians(x1_deg - x0_deg);
    const y0 = radians(y0_deg);
    const y1 = radians(y1_deg);

    var root = (sqr(std.math.sin(dY / 2.0))) + std.math.cos(y0) * std.math.cos(y1) * sqr(std.math.sin(dX / 2));
    return 2.0 * radius * std.math.asin(std.math.sqrt(root));
}

pub fn processFile(absolute_path: []const u8) !Result {
    var timer = try std.time.Timer.start();

    const file = try std.fs.openFileAbsolute(absolute_path, .{});
    defer file.close();
    var input_data = try file.readToEndAlloc(heap_alloc, ~@intCast(usize, 0));
    defer heap_alloc.free(input_data);

    var stream = std.json.TokenStream.init(input_data);
    const Template = struct {
        pairs: []Pair,
    };
    const options = .{ .allocator = heap_alloc, .ignore_unknown_fields = json_ignore_unknown_fields };
    const result = try std.json.parse(Template, &stream, options);
    defer std.json.parseFree(Template, result, options);

    const parse_time = timer.lap();

    var sum: Float = 0;
    for (result.pairs) |p| {
        sum += haversineDistance(p.x0, p.y0, p.x1, p.y1, earth_radius);
    }

    const process_time = timer.read();

    return .{ .count = result.pairs.len, .sum = sum, .parse_time = parse_time, .process_time = process_time };
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
                try gen(test_path, n);
            } else {
                print("Argument '-n' expects integer after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-f")) {
            // SET FILE
            ai += 1;
            if (ai < args.len) {
                heap_alloc.free(test_path);
                test_path = try std.fs.path.join(heap_alloc, &.{ exe_path, args[ai] });
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
                    print("-----------------------------------------\n", .{});
                    print("{}#\n", .{i});
                    print("\t" ++ "avg harvestine: {d:.5}\n", .{res.sum / @intToFloat(Float, res.count)});
                    print("\t" ++ "read & parse time: {}\n", .{fmtDuration(res.parse_time)});
                    print("\t" ++ "process time: {}\n", .{fmtDuration(res.process_time)});
                    print("\t" ++ "total time: {}\n", .{fmtDuration(res.total_time)});
                }

                total_res.parse_time = std.math.min(total_res.parse_time, res.parse_time);
                total_res.process_time = std.math.min(total_res.process_time, res.process_time);
                total_res.total_time = std.math.min(total_res.total_time, res.total_time);
                
                total_res.count = res.count;
                total_res.sum = res.sum;
            }
            //if (i > 1 or !print_each_test_iteration)
            {
                const res = total_res;
                print("=======================================\nBEST SUB-RESULTS:\n", .{});
                print("(test-iterations: {}, input size: {}, float: {})\n", .{total_iterations, res.count, Float});
                print("\t" ++ "read & parse time: {}\n", .{fmtDuration(res.parse_time)});
                print("\t" ++ "process time: {}\n", .{fmtDuration(res.process_time)});
                print("\t" ++ "total time: {}\n", .{fmtDuration(res.total_time)});
                print("\t" ++ "haversine throughput: {} haversines/second\n", .{res.count * std.time.ns_per_s / res.total_time});
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
    sum: Float = std.math.nan(Float),

    parse_time: u64 = std.math.maxInt(u64),
    process_time: u64 = std.math.maxInt(u64),
    total_time: u64 = std.math.maxInt(u64),
};

// TESTS
const json_unordered_with_junk =
    \\{
    \\  "z_anything_but_pairs": [ {
    \\			"x0": 0,
    \\			"y0": 0,
    \\			"x1": 0,
    \\			"y1": 0
    \\		}
    \\  ],
    \\	"pairs": [{
    \\          "foo" : "bar",
    \\			"x0": 115.124,
    \\			"y0": -87.123,
    \\			"x1": -123,
    \\			"y1": 15.40
    \\		},
    \\		{
    \\			"y1": 95.40,
    \\			"y0": -7.323,
    \\          "planet" : "earth",
    \\			"x0": 315.124,
    \\			"x1": -123
    \\		}
    \\	],
    \\  "some random other data" : { "x0": 5}
    \\}
;

test "test_default_json_parse" {
    var stream = std.json.TokenStream.init(json_unordered_with_junk);
    const Template = struct {
        pairs: []Pair,
    };
    const options = .{
        .allocator = std.testing.allocator,
        .ignore_unknown_fields = true,
    };
    const result = try std.json.parse(Template, &stream, options);
    defer std.json.parseFree(Template, result, options);

    try std.testing.expectEqual(result.pairs.len, 2);
    try std.testing.expectEqual(result.pairs[0].x0, 115.124);
    try std.testing.expectEqual(result.pairs[0].y0, -87.123);
    try std.testing.expectEqual(result.pairs[0].x1, -123);
    try std.testing.expectEqual(result.pairs[0].y1, 15.4);

    try std.testing.expectEqual(result.pairs[1].x0, 315.124);
    try std.testing.expectEqual(result.pairs[1].y0, -7.323);
    try std.testing.expectEqual(result.pairs[1].x1, -123);
    try std.testing.expectEqual(result.pairs[1].y1, 95.4);
}
