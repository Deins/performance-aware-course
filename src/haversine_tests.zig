const std = @import("std");

const Float = f64;
const Pair = struct { x0: Float, y0: Float, x1: Float, y1: Float };

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
