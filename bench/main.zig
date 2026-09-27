const std = @import("std");
const zm = @import("zmetrics");
const zbench = @import("zbench");

const BUF_LEN = 1_000_000;

// Scalar
var pcg = zm.rand.Pcgrng.init(21343234);
var rng = pcg.randomGen();

// SIMD
var pcg_simd = zm.rand.PcgrngSimd(8).init(21343234);
var rng_simd = pcg_simd.randomGen();

// SIMD 16
var pcg_simd_16 = zm.rand.PcgrngSimd(16).init(21343234);
var rng_simd_16 = pcg_simd.randomGen();

var u32_buf: []u32 = undefined;
var f32_buf: []f32 = undefined;

var sink: u32 = 0;
var sink2: f32 = 0;

fn fillU32(_: std.mem.Allocator) void {
    rng.fillRandom(u32, u32_buf);
    sink = u32_buf[0];
}

fn fillF32(_: std.mem.Allocator) void {
    rng.fillRandom(f32, f32_buf);
    sink2 = f32_buf[0];
}

fn fillSimdU32(_: std.mem.Allocator) void {
    rng_simd.fillRandom(u32, u32_buf);
    sink = u32_buf[0];
}

fn fillSimdF32(_: std.mem.Allocator) void {
    rng_simd.fillRandom(f32, f32_buf);
    sink2 = f32_buf[0];
}

fn fillSimd16U32(_: std.mem.Allocator) void {
    rng_simd.fillRandom(u32, u32_buf);
    sink = u32_buf[0];
}

fn fillSimd16F32(_: std.mem.Allocator) void {
    rng_simd.fillRandom(f32, f32_buf);
    sink2 = f32_buf[0];
}

pub fn main(init: std.process.Init) !void {
    var arena_ = std.heap.ArenaAllocator.init(init.gpa);
    defer arena_.deinit();

    const arena = arena_.allocator();

    u32_buf = try arena.alloc(u32, BUF_LEN);
    f32_buf = try arena.alloc(f32, BUF_LEN);

    var bench = zbench.Benchmark.init(arena, .{});
    defer bench.deinit();

    // Scalar
    try bench.add("scalar fill 1M u32", fillU32, .{});
    try bench.add("scalar fill 1M f32", fillF32, .{});

    // SIMD 8
    try bench.add("simd8 fill 1M u32", fillSimdU32, .{});
    try bench.add("simd8 fill 1M f32", fillSimdF32, .{});

    // SIMD 16
    try bench.add("simd16 fill 1M u32", fillSimd16U32, .{});
    try bench.add("simd16 fill 1M f32", fillSimd16F32, .{});

    try bench.run(init.io, std.Io.File.stdout());
}
