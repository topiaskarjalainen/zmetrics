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
