//! The compiled body of a class or function.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Vm = @import("Vm.zig");
const Value = @import("Value.zig");

pub const Index = enum(u32) { _ };

pub const OpCode = enum(u8) {
    pop,
    push_nil,
    push_true,
    push_false,
    push_constant,

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
offsets: ArrayList(usize),
constants: ArrayList(Value),

pub const empty = Proto{
    .code = .empty,
    .offsets = .empty,
    .constants = .empty,
};

pub fn deinit(p: *Proto, gpa: Allocator) void {
    p.code.deinit(gpa);
    p.offsets.deinit(gpa);
    p.constants.deinit(gpa);
    p.* = undefined;
}

pub fn write(p: *Proto, gpa: Allocator, op: OpCode, offset: usize) !void {
    try p.code.append(gpa, op);
    try p.offsets.append(gpa, offset);
}

pub fn writeByte(p: *Proto, gpa: Allocator, byte: u8, offset: usize) !void {
    return p.write(gpa, @enumFromInt(byte), offset);
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
    if (offset > 0 and p.offsets.items[offset] == p.offsets.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:>4} ", .{p.offsets.items[offset]});
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
        .push_constant => {
            const index = @intFromEnum(p.code.items[offset + 1]);
            std.debug.print("{s:<16} {d:>4} '{f}'\n", .{ @tagName(instruction), index, p.constants.items[index] });
            return offset + 2;
        },
        _ => {
            std.debug.print("unknown opcode\n", .{});
            return offset + 1;
        },
    }
}
