const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Vm = @import("Vm.zig");
const Value = @import("Value.zig");

pub const OpCode = enum(u8) {
    constant,

    // unary
    negate,

    // binary
    add,
    sub,
    mul,
    div,

    ret,
    _,
};

const Chunk = @This();

code: ArrayList(OpCode),
lines: ArrayList(usize),
constants: ArrayList(Value),

pub const empty = Chunk{
    .code = .empty,
    .lines = .empty,
    .constants = .empty,
};

pub fn deinit(chunk: *Chunk, gpa: Allocator) void {
    chunk.code.deinit(gpa);
    chunk.lines.deinit(gpa);
    chunk.constants.deinit(gpa);
    chunk.* = undefined;
}

pub fn write(chunk: *Chunk, gpa: Allocator, op: OpCode, line: usize) !void {
    try chunk.code.append(gpa, op);
    try chunk.lines.append(gpa, line);
}

pub fn writeByte(chunk: *Chunk, gpa: Allocator, byte: u8, line: usize) !void {
    return chunk.write(gpa, @enumFromInt(byte), line);
}

pub fn addConstant(chunk: *Chunk, gpa: Allocator, value: Value) !usize {
    try chunk.constants.append(gpa, value);
    return chunk.constants.items.len - 1;
}

pub fn disassemble(chunk: Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = chunk.disassembleInstruction(offset);
    }
}

pub fn disassembleInstruction(chunk: Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});
    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:>4} ", .{chunk.lines.items[offset]});
    }

    const instruction = chunk.code.items[offset];
    switch (instruction) {
        .ret, .negate, .add, .sub, .mul, .div => {
            std.debug.print("{s}\n", .{@tagName(instruction)});
            return offset + 1;
        },
        .constant => {
            const index = @intFromEnum(chunk.code.items[offset + 1]);
            std.debug.print("{s:<16} {d:>4} '{f}'\n", .{ @tagName(instruction), index, chunk.constants.items[index] });
            return offset + 2;
        },
        _ => {
            std.debug.print("unknown opcode\n", .{});
            return offset + 1;
        },
    }
}
