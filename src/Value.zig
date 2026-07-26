const std = @import("std");

const Value = @This();

data: f64,

pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("{d}", .{self.data});
}
