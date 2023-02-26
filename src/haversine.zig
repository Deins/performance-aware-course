const std = @import("std");

const Float = f64;
const Pair = struct { x0: Float, y0: Float, x1: Float, y1: Float };
const earth_radius = 6371.0;
var total_iterations : usize = 1;

const Result = struct {
    count: usize = 0,
    sum: Float = std.math.nan(Float),

    parse_time: u64 = std.math.maxInt(u64),
    process_time: u64 = std.math.maxInt(u64),
    total_time: u64 = std.math.maxInt(u64),
};
var total_res : Result = .{};

var heap: std.heap.GeneralPurposeAllocator(.{}) = .{};
var heap_alloc = heap.allocator();

pub fn gen(absolute_path: []const u8, pair_count: usize) !void {
    var timer = try std.time.Timer.start();

    const file = try std.fs.createFileAbsolute(absolute_path, .{ .truncate = true });
    defer file.close();
    // TODO: buffering?
    var writer = file.writer();
    try writer.writeAll("{\"pairs\":[\n");

    const seed = 0x12345;
    var rand = std.rand.DefaultPrng.init(seed);
    var i: usize = 1;
    if (pair_count > 0) {
        while (i < pair_count) : (i += 1) {
            //std.debug.print
            try writer.print("{{\"x0\":{d:.5},\"y0\":{d:.5},\"x1\":{d:.5},\"y1\":{d:.5}}},\n", .{
                rand.random().float(Float) * 360 - 180,
                rand.random().float(Float) * 360 - 180,
                rand.random().float(Float) * 360 - 180,
                rand.random().float(Float) * 360 - 180,
            });
        }
        // tail without ending with
        try writer.print("{{\"x0\":{d:.5},\"y0\":{d:.5},\"x1\":{d:.5},\"y1\":{d:.5}}}\n", .{
            rand.random().float(Float) * 360 - 180,
            rand.random().float(Float) * 360 - 180,
            rand.random().float(Float) * 360 - 180,
            rand.random().float(Float) * 360 - 180,
        });
    }

    try writer.writeAll(
        \\ ]}
    );

    std.debug.print("gen done in {}\n", .{std.fmt.fmtDuration(timer.read())});
}

pub fn radians(degrees: Float) Float {
    return degrees * (std.math.pi / 180.0);
}

fn sqr(x: Float) Float {
    return x * x;
}

pub fn haversine_distance(x0_deg: Float, y0_deg: Float, x1_deg: Float, y1_deg: Float, radius: Float) Float {
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
    const options = .{ .allocator = heap_alloc };
    const result = try std.json.parse(Template, &stream, options);
    defer std.json.parseFree(Template, result, options);
    const parse_time = timer.read();

    timer.reset();
    var sum: Float = 0;
    for (result.pairs) |p| {
        sum += haversine_distance(p.x0, p.y0, p.x1, p.y1, earth_radius);
    }
    return .{ .count = result.pairs.len, .sum = sum, .parse_time = parse_time, .process_time = timer.read() };
}

pub fn main() !void {
    var exe_path_buff: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const exe_path = try std.fs.selfExeDirPath(&exe_path_buff);
    var test_path = try std.fs.path.join(heap_alloc, &.{ exe_path, "test.json" });
    defer heap_alloc.free(test_path);

    const args = try std.process.argsAlloc(heap_alloc);
    defer std.process.argsFree(heap_alloc, args);

    var ai: usize = 0;
    while (ai < args.len) : (ai += 1) {
        if (std.ascii.eqlIgnoreCase(args[ai], "-g")) {
            // GENERATE
            ai += 1;
            if (ai < args.len) {
                var n = std.fmt.parseInt(usize, args[ai], 10) catch |err| {
                    std.debug.print("Argument '-n' expects integer after it, parse error: {}\n", .{err});
                    return;
                };
                try gen(test_path, n);
            } else {
                std.debug.print("Argument '-n' expects integer after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-f")) {
            // SET FILE
            ai += 1;
            if (ai < args.len) {
                heap_alloc.free(test_path);
                test_path = try std.fs.path.join(heap_alloc, &.{ exe_path, args[ai] });
            } else {
                std.debug.print("Argument '-f' expects file name after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-r")) {
            // RUN
            var i: i32 = 0;
            while (i < total_iterations) : (i += 1) {
                var timer = try std.time.Timer.start();
                var res = try processFile(test_path);
                res.total_time = timer.read();
                
                std.debug.print("-----------------------------------------\n", .{});
                std.debug.print("{}#\n", .{i});
                std.debug.print("avg harvestine: {d:.5}\n", .{res.sum / @intToFloat(Float, res.count)});
                std.debug.print("parse time: {}\n", .{std.fmt.fmtDuration(res.parse_time)});
                std.debug.print("process time: {}\n", .{std.fmt.fmtDuration(res.process_time)});
                std.debug.print("total time: {}\n", .{std.fmt.fmtDuration(res.total_time)});

                total_res.parse_time = std.math.min(total_res.parse_time, res.parse_time);
                total_res.process_time = std.math.min(total_res.parse_time, res.process_time);
                total_res.total_time = std.math.min(total_res.total_time, res.total_time);
            }
            if (i > 1) {
                const res = total_res;
                std.debug.print("=======================================\n TOTAL BEST: \n", .{});
                std.debug.print("parse time: {}\n", .{std.fmt.fmtDuration(res.parse_time)});
                std.debug.print("process time: {}\n", .{std.fmt.fmtDuration(res.process_time)});
                std.debug.print("total time: {}\n", .{std.fmt.fmtDuration(res.total_time)});
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-i")) {
            // SET ITERATIONS
            ai += 1;
            if (ai < args.len) {
                total_iterations = std.fmt.parseInt(usize, args[ai], 10) catch |err| {
                    std.debug.print("Argument '-i' expects integer after it, parse error: {}\n", .{err});
                    return;
                };
            } else {
                std.debug.print("Argument '-i' expects integer after it\n", .{});
                return;
            }
        } else if (std.ascii.eqlIgnoreCase(args[ai], "-h") or std.ascii.eqlIgnoreCase(args[ai], "--help")) {
            // HELP
            std.debug.print("Help: \n  Runs commands in order possible commands: \n", .{});
            std.debug.print("\t-f X \t\t switch json in/out file to file named X\n", .{});
            std.debug.print("\t-g X \t\t generates json file (previously specified with -f) with X pairs\n", .{});
            std.debug.print("\t-r X \t\t run the harvestine processing\n", .{});
            std.debug.print("\t-i X \t\t how many iterations to run to gather best execution time \n", .{});
        }
    }
}

// TESTS
test "test_default_json_parse" {
    const test_json =
        \\{
        \\	"pairs": [{
        \\			"x0": 115.124,
        \\			"y0": -87.123,
        \\			"x1": -123,
        \\			"y1": 15.40
        \\		},
        \\		{
        \\			"x0": 315.124,
        \\			"y0": -7.323,
        \\			"x1": -123,
        \\			"y1": 95.40
        \\		}
        \\	]
        \\}
    ;

    var stream = std.json.TokenStream.init(test_json);
    const Template = struct {
        pairs: []Pair,
    };
    const options = .{ .allocator = std.testing.allocator };
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
