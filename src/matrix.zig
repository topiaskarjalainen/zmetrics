const std = @import("std");

pub const SimpleMatrix = struct {
    const Self = @This();

    nrow: usize,
    ncol: usize,
    data: []f32,

    pub fn init(nrow: usize, ncol: usize, data: []f32) Self {
        std.debug.assert(data.len == nrow * ncol);
        return .{
            .nrow = nrow,
            .ncol = ncol,
            .data = data,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    pub fn at(self: Self, row: usize, col: usize) *f32 {
        std.debug.assert(row < self.nrow);
        std.debug.assert(col < self.ncol);

        return &self.data[row * self.ncol + col];
    }

    pub fn allocateData(nrow: usize, ncol: usize, allocator: std.mem.Allocator) ![]f32 {
        const data = try allocator.alloc(f32, ncol * nrow);
        errdefer allocator.free(data);
        return data;
    }

    pub fn cholesky(self: *Self, out_buf: []f32) void {
        @memset(out_buf, 0.0);

        var i = 0;
        var j = 0;
        while (i < self.ncol) : (i += 1) {
            while (j < self.nrow) : (j += 1) {
                var sum = 0.0;
                for
            }
        }
    }
};
