const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const MultiArrayList = std.MultiArrayList;
const Writer = std.Io.Writer;

const Chunk = @import("Chunk.zig");
const Compilation = @import("Compilation.zig");
const debug = @import("debug.zig");
const Value = @import("Value.zig");

pub const STACK_MAX = 256;

const Vm = @This();

gpa: Allocator,
arena: Allocator,
io: Io,
writer: *Writer,

chunk: *Chunk = undefined,
ip: usize = 0,

stack: []Value,
// index after top item
stack_top: usize = 0,
// objects: MultiArrayList(Value.Object)

pub const InitOptions = struct {
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    writer: *Writer,
    stack_max: usize = std.math.pow(usize, 2, 10),
};

/// `arena` must live as long as the VM.
pub fn init(options: InitOptions) !Vm {
    return Vm{
        .gpa = options.gpa,
        .arena = options.arena,
        .io = options.io,
        .writer = options.writer,
        .stack = try options.gpa.alloc(Value, options.stack_max),
    };
}

pub fn deinit(vm: *Vm) void {
    vm.gpa.free(vm.stack);
    vm.* = undefined;
}

pub const InterpretResult = enum { ok, compile_error, runtime_error };

pub fn interpret(vm: *Vm, source: [:0]const u8) !InterpretResult {
    try Compilation.compile(vm, source);
    return .ok;
}

fn run(vm: *Vm) !InterpretResult {
    while (true) {
        if (debug.TRACE_EXECUTION) {
            std.debug.print("          ", .{});
            for (0..vm.stack_top) |slot| {
                std.debug.print("[ {f} ]", .{vm.stack[slot]});
            }
            std.debug.print("\n", .{});

            _ = vm.chunk.disassembleInstruction(vm.ip);
        }

        const op = vm.readOp();
        switch (op) {
            .constant => {
                const constant = vm.readConstant();
                vm.push(constant);
            },
            .add, .sub, .mul, .div => {
                const b = vm.pop();
                const a = vm.pop();
                vm.push(.{ .data = switch (op) {
                    .add => a.data + b.data,
                    .sub => a.data - b.data,
                    .mul => a.data * b.data,
                    .div => a.data / b.data,
                    else => unreachable,
                } });
            },
            .negate => {
                vm.push(.{ .data = -vm.pop().data });
            },
            .ret => {
                try vm.writer.print("{f}\n", .{vm.pop()});
                try vm.writer.flush();
                return .ok;
            },
            _ => unreachable,
        }
    }
}

fn push(vm: *Vm, value: Value) void {
    vm.stack[vm.stack_top] = value;
    vm.stack_top += 1;
}

fn pop(vm: *Vm) Value {
    vm.stack_top -= 1;
    return vm.stack[vm.stack_top];
}

fn readOp(vm: *Vm) Chunk.OpCode {
    const op = vm.chunk.code.items[vm.ip];
    vm.ip += 1;
    return op;
}

fn readByte(vm: *Vm) u8 {
    return @intFromEnum(vm.readOp());
}

fn readConstant(vm: *Vm) Value {
    return vm.chunk.constants.items[vm.readByte()];
}
