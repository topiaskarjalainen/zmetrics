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

    pub fn cholesky(self: *Self, out_matrix: *SimpleMatrix) void {
        std.debug.assert(self.nrow == self.ncol);
        std.debug.assert(out_matrix.nrow == self.nrow);
        std.debug.assert(out_matrix.ncol == self.ncol);
        const n = self.nrow;
        @memset(out_matrix.data, 0.0);
        for (0..n) |i| {
            for (0..i) |j| {
                var sum: f32 = 0.0;
                for (0..j) |k| {
                    sum += out_matrix.at(i, k).* * out_matrix.at(j, k).*;
                }
                out_matrix.at(i, j).* =
                    (self.at(i, j).* - sum) / out_matrix.at(j, j).*;
            }
            var sum: f32 = 0.0;
            for (0..i) |k| {
                const value = out_matrix.at(i, k).*;
                sum += value * value;
            }
            out_matrix.at(i, i).* =
                @sqrt(self.at(i, i).* - sum);
        }
    }

    pub fn allocateSimiliar(self: *Self, allocator: std.mem.Allocator) !SimpleMatrix {
        return allocateLike(self, allocator);
    }

    pub fn print(self: Self) void {
        for (0..self.nrow) |i| {
            for (0..self.ncol) |j| {
                std.debug.print("{d:.4} ", .{self.at(i, j).*});
            }
            std.debug.print("\n", .{});
        }
    }

    fn allocateLike(kind: *SimpleMatrix, alloc: std.mem.Allocator) !SimpleMatrix {
        const data = try alloc.alloc(f32, kind.ncol * kind.nrow);
        errdefer alloc.free(data);
        return .{
            .ncol = kind.ncol,
            .nrow = kind.nrow,
            .data = data,
        };
    }
};

test "Cholesky" {
    const allocator = std.testing.allocator;

    var data = try allocator.alloc(f32, 4);
    defer allocator.free(data);

    data[0] = 4;
    data[1] = 2;
    data[2] = 2;
    data[3] = 3;

    var matrix = SimpleMatrix.init(2, 2, data);

    var L = try SimpleMatrix.allocateLike(&matrix, allocator);
    defer L.deinit(allocator);

    matrix.cholesky(&L);

    matrix.print();
    L.print();

    try std.testing.expectApproxEqAbs(@as(f32, 2.0), L.at(0, 0).*, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), L.at(0, 1).*, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), L.at(1, 0).*, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.4142135), L.at(1, 1).*, 0.0001);
}
