const std = @import("std");

const Ast = @import("Ast.zig");
const Vm = @import("Vm.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const debug = @import("debug.zig");

const Compiler = @This();

vm: *Vm,

pub fn compile(vm: *Vm, source: [:0]const u8) !void {
    var tree = try Ast.parse(vm.gpa, source);
    defer tree.deinit(vm.gpa);

    std.debug.print("error count: {d}\n", .{tree.errors.len});
    for (tree.errors) |e| {
        try tree.renderError(e, vm.writer);
        try vm.writer.writeAll("\n");
        try vm.writer.flush();
    }
}
