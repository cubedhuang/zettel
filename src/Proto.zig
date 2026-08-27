//! The compiled body of a class or function.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Source = @import("Source.zig");
const Vm = @import("Vm.zig");
const Value = @import("Value.zig");

pub const Index = enum(u32) { _ };

pub const OpCode = enum(u8) {
    pop,
    push_nil,
    push_true,
    push_false,
    push_constant,

    get_global,
    define_global,
    set_global,

    // unary
    bool_not,
    negate,

    // binary
    cmp_eq,
    cmp_neq,
    cmp_gt,
    cmp_gte,
    cmp_lt,
    cmp_lte,
    add,
    sub,
    mul,
    div,

    ret,
    _,
};

const Proto = @This();

code: ArrayList(OpCode),
/// TODO: run-length encoding or something similar
spans: ArrayList(Source.Span),
constants: ArrayList(Value),

pub const empty = Proto{
    .code = .empty,
    .spans = .empty,
    .constants = .empty,
};

pub fn deinit(p: *Proto, gpa: Allocator) void {
    p.code.deinit(gpa);
    p.spans.deinit(gpa);
    p.constants.deinit(gpa);
    p.* = undefined;
}

pub fn write(p: *Proto, gpa: Allocator, op: OpCode, span: Source.Span) !void {
    try p.code.append(gpa, op);
    try p.spans.append(gpa, span);
}

pub fn writeByte(p: *Proto, gpa: Allocator, byte: u8, span: Source.Span) !void {
    return p.write(gpa, @enumFromInt(byte), span);
}

pub fn addConstant(p: *Proto, gpa: Allocator, value: Value) !u8 {
    try p.constants.append(gpa, value);
    return @intCast(p.constants.items.len - 1);
}

pub fn disassemble(p: Proto, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < p.code.items.len) {
        offset = p.disassembleInstruction(offset);
    }
}

pub fn disassembleInstruction(p: Proto, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (offset > 0 and std.meta.eql(p.spans.items[offset], p.spans.items[offset - 1])) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:>4} ", .{p.spans.items[offset].start});
    }

    const instruction = p.code.items[offset];
    switch (instruction) {
        .pop,
        .push_nil,
        .push_true,
        .push_false,
        .ret,
        .bool_not,
        .negate,
        .cmp_eq,
        .cmp_neq,
        .cmp_gt,
        .cmp_gte,
        .cmp_lt,
        .cmp_lte,
        .add,
        .sub,
        .mul,
        .div,
        => {
            std.debug.print("{s}\n", .{@tagName(instruction)});
            return offset + 1;
        },
        .push_constant,
        .get_global,
        .define_global,
        .set_global,
        => {
            const index = @intFromEnum(p.code.items[offset + 1]);
            std.debug.print("{s:<16} {d:>4} `{f}`\n", .{ @tagName(instruction), index, p.constants.items[index] });
            return offset + 2;
        },
        _ => {
            std.debug.print("unknown opcode\n", .{});
            return offset + 1;
        },
    }
}
