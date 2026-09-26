//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const rand = @import("pcg_rand.zig");
