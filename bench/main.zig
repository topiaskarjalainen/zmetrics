const std = @import("std");
const zm = @import("zmetrics");
const zbench = @import("zbench");

var pcg = zm.Pcgrng.init(21343234);
var rng = pcg.randomGen();

var u32_buf: [1000]u32 = undefined;
var f32_buf: [1000]f32 = undefined;

fn fillU32(_: std.mem.Allocator) void {
    rng.fillRandom(u32, &u32_buf);
}

fn fillF32(_: std.mem.Allocator) void {
    rng.fillRandom(f32, &f32_buf);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    var bench = zbench.Benchmark.init(arena, .{});
    defer bench.deinit();

    try bench.add("fill 1000 u32", fillU32, .{});
    try bench.add("fill 1000 f32", fillF32, .{});

    try bench.run(init.io, std.Io.File.stdout());
}
