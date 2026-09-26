const std = @import("std");
const zbench = @import("zbench");
const zm = @import("zmetrics");

var pcg = zm


var buffer: [1000]u32 = undefined;

fn fillRandomU32(_: std.mem.Allocator) void {
    rng.fillRandom(u32, &buffer);
}

test "benchmark random u32 fill" {
    const stdout: std.Io.File = .stdout();

    var bench = zbench.Benchmark.init(std.testing.allocator, .{});
    defer bench.deinit();

    try bench.add("Pcgrng fill 1000 u32", fillRandomU32, .{});

    try bench.run(std.testing.io, stdout);
}
