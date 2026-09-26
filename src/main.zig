const std = @import("std");
const Io = std.Io;

const zmetrics = @import("zmetrics");

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }
    // In order to do I/O operations need an `Io` instance.
    // const io = init.io;

}
