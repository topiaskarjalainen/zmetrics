const std = @import("std");

pub const RandomGen = struct {
    ctx: *anyopaque,

    getNextRandomU32Fn: *const fn (ctx: *anyopaque) u32,
    getNextRandomF32Fn: *const fn (ctx: *anyopaque) f32,

    fillRandomU32Fn: *const fn (ctx: *anyopaque, buf: []u32) void,
    fillRandomF32Fn: *const fn (ctx: *anyopaque, buf: []f32) void,

    pub fn getNextRandom(self: *RandomGen, comptime T: type) T {
        return switch (T) {
            u32 => self.getNextRandomU32Fn(self.ctx),
            f32 => self.getNextRandomF32Fn(self.ctx),
            else => @compileError("unsupported random type"),
        };
    }

    pub fn fillRandom(self: *RandomGen, comptime T: type, buf: []T) void {
        switch (T) {
            u32 => self.fillRandomU32Fn(self.ctx, buf),
            f32 => self.fillRandomF32Fn(self.ctx, buf),
            else => @compileError("unsupported random type"),
        }
    }
};

const F32_SCALE: f32 = std.math.pow(f32, 2.0, -24.0);

pub const Pcgrng = struct {
    state: u64,

    const MULTIPLIER: u64 = 6364136223846793005;
    const INCREMENT: u64 = 1442695040888963407;

    pub fn init(seed: u64) Pcgrng {
        var rng = Pcgrng{
            .state = 0,
        };

        rng.state = rng.state *% MULTIPLIER +% INCREMENT;
        rng.state +%= seed;
        _ = rng.getNextRandomU32();

        return rng;
    }

    fn getNextRandomU32(self: *Pcgrng) u32 {
        const old_state = self.state;

        self.state = old_state *% MULTIPLIER +% INCREMENT;

        const xorshifted: u32 = @truncate(
            ((old_state >> 18) ^ old_state) >> 27,
        );

        const rot: u32 = @truncate(old_state >> 59);

        return (xorshifted >> @intCast(rot)) |
            (xorshifted << @intCast((@as(u32, 0) -% rot) & 31));
    }

    fn getNextRandomF32(self: *Pcgrng) f32 {
        const a = self.getNextRandomU32();
        const masked = a & 0x00ff_ffff;

        return @as(f32, @floatFromInt(masked)) * F32_SCALE;
    }

    fn fillRandomU32(ctx: *anyopaque, buf: []u32) void {
        const self: *Pcgrng = @ptrCast(@alignCast(ctx));

        for (buf) |*x| {
            x.* = self.getNextRandomU32();
        }
    }

    fn fillRandomF32(ctx: *anyopaque, buf: []f32) void {
        const self: *Pcgrng = @ptrCast(@alignCast(ctx));

        for (buf) |*x| {
            x.* = self.getNextRandomF32();
        }
    }

    fn getRandomU32(ctx: *anyopaque) u32 {
        const self: *Pcgrng = @ptrCast(@alignCast(ctx));
        return self.getNextRandomU32();
    }

    fn getRandomF32(ctx: *anyopaque) f32 {
        const self: *Pcgrng = @ptrCast(@alignCast(ctx));
        return self.getNextRandomF32();
    }

    pub fn randomGen(self: *Pcgrng) RandomGen {
        return .{
            .ctx = self,

            .getNextRandomU32Fn = getRandomU32,
            .getNextRandomF32Fn = getRandomF32,

            .fillRandomU32Fn = fillRandomU32,
            .fillRandomF32Fn = fillRandomF32,
        };
    }
};

test "Fill buffer with u32" {
    var pcg = Pcgrng.init(234);
    var rng = pcg.randomGen();

    var buff: [100]u32 = undefined;

    rng.fillRandom(u32, &buff);
    for (buff) |value| {
        std.debug.print("{} ", .{value});
    }
    std.debug.print("\n", .{});
}

test "Fill buffer with f32" {
    var pcg = Pcgrng.init(234);
    var rng = pcg.randomGen();

    var buff: [100]f32 = undefined;

    rng.fillRandom(f32, &buff);
    for (buff) |value| {
        std.debug.print("{} ", .{value});
    }
    std.debug.print("\n", .{});
}

pub fn PcgrngSimd(comptime lane_count: usize) type {
    return struct {
        const Self = @This();

        pub const Lanes = lane_count;

        const StateVec = @Vector(lane_count, u64);
        const U32Vec = @Vector(lane_count, u32);
        const F32Vec = @Vector(lane_count, f32);
        state: StateVec,
        const MULTIPLIER: u64 = 6364136223846793005;
        const INCREMENT: u64 = 1442695040888963407;

        fn wrappingMulAdd(
            a: StateVec,
            b: StateVec,
            c: StateVec,
        ) StateVec {
            const mul = @mulWithOverflow(a, b);
            const add = @addWithOverflow(mul[0], c);
            return add[0];
        }

        pub fn init(seed: u64) Self {
            var rng = Self{
                .state = @splat(seed),
            };
            inline for (0..Lanes) |i| {
                rng.state[i] = seed +% @as(u64, i);
            }
            _ = rng.nextU32();
            return rng;
        }

        fn nextU32(self: *Self) U32Vec {
            const old_state = self.state;

            self.state =
                old_state *% @as(StateVec, @splat(MULTIPLIER)) +%
                @as(StateVec, @splat(INCREMENT));

            const xorshifted: U32Vec = @truncate(
                ((old_state >> @as(StateVec, @splat(18))) ^ old_state) >> @as(StateVec, @splat(27)),
            );

            const rot: U32Vec = @truncate(
                old_state >> @as(StateVec, @splat(59)),
            );

            const inv_rot: U32Vec =
                (@as(U32Vec, @splat(32)) - rot) &
                @as(U32Vec, @splat(31));

            const rot_u5: @Vector(lane_count, u5) = @truncate(rot);
            const inv_rot_u5: @Vector(lane_count, u5) = @truncate(inv_rot);

            return (xorshifted >> rot_u5) |
                (xorshifted << inv_rot_u5);
        }

        fn nextF32(self: *Self) F32Vec {
            const values = self.nextU32();
            const masked = values & @as(U32Vec, @splat(0x00ff_ffff));
            return @as(F32Vec, @floatFromInt(masked)) * @as(F32Vec, @splat(F32_SCALE));
        }

        fn getRandomU32(ctx: *anyopaque) u32 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.nextU32()[0];
        }

        fn getRandomF32(ctx: *anyopaque) f32 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.nextF32()[0];
        }

        fn fillRandomU32(ctx: *anyopaque, buf: []u32) void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            var i: usize = 0;

            while (i + lane_count <= buf.len) : (i += lane_count) {
                const values = self.nextU32();

                inline for (0..lane_count) |lane| {
                    buf[i + lane] = values[lane];
                }
            }
            while (i < buf.len) : (i += 1) {
                buf[i] = self.nextU32()[0];
            }
        }

        fn fillRandomF32(ctx: *anyopaque, buf: []f32) void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            var i: usize = 0;

            while (i + lane_count <= buf.len) : (i += lane_count) {
                const values = self.nextF32();

                inline for (0..lane_count) |lane| {
                    buf[i + lane] = values[lane];
                }
            }
            while (i < buf.len) : (i += 1) {
                buf[i] = self.nextF32()[0];
            }
        }

        pub fn randomGen(self: *Self) RandomGen {
            return .{
                .ctx = self,

                .getNextRandomU32Fn = getRandomU32,
                .getNextRandomF32Fn = getRandomF32,

                .fillRandomU32Fn = fillRandomU32,
                .fillRandomF32Fn = fillRandomF32,
            };
        }
    };
}

pub const PcgrngSimd4 = PcgrngSimd(4);
pub const PcgrngSimd8 = PcgrngSimd(8);
pub const PcgrngSimd16 = PcgrngSimd(16);

pub const RandomDist = struct {
    ctx: *anyopaque,

    getNextRandomF32: *const fn (ctx: *anyopaque) f32,
    fillRandomF32: *const fn (ctx: *anyopaque, buf: []f32) void,
};

pub const RandomNormal2 = struct {
    const Self = @This();

    rng: *RandomGen,
    mu: f32,
    sd: f32,

    pub fn init() Self {}

    fn randomVariate(self: *Self) [2]f32 {
        var val = [2]f32{ 0, 0 };
        self.oneSample(&val);
        return val;
    }

    fn oneSample(self: *Self, out: *[2]f32) void {
        const u1_ = @max(self.rng.getNextRandom(f32), std.math.floatEps(f32));
        const u2_ = self.rng.getNextRandom(f32);
        const r = @sqrt(-2.0 * @log(u1_));
        const theta = 2.0 * std.math.pi * u2_;
        out[0] = self.mu + self.sd * r * @cos(theta);
        out[1] = self.mu + self.sd * r * @sin(theta);
    }

    fn sampleIntoArray(self: *Self, out_buf: []f32) void {
        var val = [2]f32{ 0, 0 };
        var i: usize = 0;
        while (i + 1 < out_buf.len) : (i += 2) {
            self.oneSample(&val);
            out_buf[i] = val[0];
            out_buf[i + 1] = val[1];
        }
        if (i < out_buf.len) {
            self.oneSample(&val);
            out_buf[i] = val[0];
        }
    }

    pub fn randomDist(self: *Self) RandomDist {
        return .{
            .ctx = self,
            .getNextRandomF32 = undefined,
            .fillRandomF32 = undefined,
        };
    }
};

pub fn RandomNormal(comptime Rng: type) type {
    return struct {
        const Self = @This();
        rng: *RandomGen,
        mu: f32,
        sd: f32,

        pub fn randomDist(self: *Self) RandomDist {
            return .{
                .ctx = self,
                .getNextRandomF32 = struct {
                    fn call(ctx: *anyopaque) f32 {
                        const norm: *Self = @ptrCast(@alignCast(ctx));
                        return norm.getNextRandomF32();
                    }
                }.call,
                .fillRandomF32 = struct {
                    fn call(ctx: *anyopaque, out_buf: []f32) f32 {
                        const norm: *Self = @ptrCast(@alignCast(ctx));
                        return norm.fillArray(out_buf);
                    }
                }.call,
            };
        }

        fn getNextRandomF32(self: *Self) f32 {
            var ret: f32 = 0.0;
            switch (Rng) {
                Pcgrng => {
                    ret = self.mu;
                },
                PcgrngSimd4 => {
                    ret = self.mu;
                },
                PcgrngSimd8 => {
                    ret = self.mu;
                },
                PcgrngSimd16 => {
                    ret = self.mu;
                },
                else => @compileError("unsupported rng"),
            }
            return ret;
        }

        fn fillArray(self: *Self, out_buf: []f32) void {
            const n = out_buf.len;
            switch (Rng) {
                Pcgrng => {
                    for (0..n) |i| {
                        out_buf[i] = self.getNextRandomF32();
                    }
                },
                PcgrngSimd4 => {},
                PcgrngSimd8 => {},
                PcgrngSimd16 => {},
                else => @compileError("unsupported rng"),
            }
        }
    };
}

test "Random normals" {
    var rng = Pcgrng.init(1232134);
    var randomGen = rng.randomGen();
    var randomNormal_ = RandomNormal(Pcgrng){
        .rng = &randomGen,
        .mu = 0.0,
        .sd = 320.0,
    };
    var randomNormal = randomNormal_.randomDist();

    var gpa = std.heap.DebugAllocator(.{}){};
    var alloc = gpa.allocator();
    const arr2 = try alloc.alloc(f32, 10_000_000);
    defer alloc.free(arr2);
    randomNormal.fillRandomF32(arr2);
    const stats = meanAndSd(arr2);

    std.debug.print("mean = {d}\n", .{stats.mean});
    std.debug.print("sd   = {d}\n", .{stats.sd});
}

fn meanAndSd(data: []const f32) struct { mean: f64, sd: f64 } {
    var mean: f64 = 0.0;
    var m2: f64 = 0.0;
    var n: u64 = 0;

    for (data) |x| {
        n += 1;

        const x64: f64 = x;
        const delta = x64 - mean;
        mean += delta / @as(f64, @floatFromInt(n));
        const delta2 = x64 - mean;

        m2 += delta * delta2;
    }

    const nf: f64 = @floatFromInt(n);
    const variance = m2 / nf;

    return .{
        .mean = mean,
        .sd = @sqrt(variance),
    };
}
