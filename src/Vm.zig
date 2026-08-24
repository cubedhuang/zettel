const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const ArrayList = std.ArrayList;
const MemoryPool = std.heap.MemoryPool;
const Writer = std.Io.Writer;

const Compilation = @import("Compilation.zig");
const Proto = @import("Proto.zig");
const Value = @import("Value.zig");
const debug = @import("debug.zig");

const Vm = @This();

gpa: Allocator,
arena: Allocator,
io: Io,
writer: *Writer,

protos: ArrayList(Proto) = .empty,
proto: *const Proto = undefined,
ip: usize = 0,

stack: []Value,
// index after top item
stack_top: usize = 0,
objects: MemoryPool(Value.Object) = .empty,
objects_head: ?*Value.Object = null,
strings: std.StringHashMap(*Value.Object),

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
        .strings = .init(options.gpa),
    };
}

pub fn deinit(vm: *Vm) void {
    for (vm.protos.items) |*proto| {
        proto.deinit(vm.gpa);
    }
    vm.protos.deinit(vm.gpa);
    vm.gpa.free(vm.stack);
    vm.freeAllObjectData();
    vm.objects.deinit(vm.gpa);
    vm.strings.deinit();
    vm.* = undefined;
}

pub fn freeAllObjectData(vm: *Vm) void {
    var current = vm.objects_head;
    while (current) |object| {
        object.freeData(vm.gpa);
        current = object.next;
    }
}

pub fn setProto(vm: *Vm, index: Proto.Index) void {
    vm.proto = vm.getProto(index);
    vm.ip = 0;
}
pub fn getProto(vm: *Vm, index: Proto.Index) *Proto {
    return &vm.protos.items[@intFromEnum(index)];
}
pub fn addProto(vm: *Vm) !Proto.Index {
    const i = vm.protos.items.len;
    try vm.protos.append(vm.gpa, .empty);
    return @enumFromInt(i);
}

pub fn copyString(vm: *Vm, data: []const u8) !*Value.Object {
    if (vm.strings.get(data)) |object| {
        return object;
    }
    const copied_data = try vm.gpa.dupe(u8, data);
    return vm.allocateString(copied_data);
}
/// `data` should be allocated with vm.gpa.
pub fn takeString(vm: *Vm, data: []const u8) !*Value.Object {
    if (vm.strings.get(data)) |object| {
        vm.gpa.free(data);
        return object;
    }
    return vm.allocateString(data);
}
pub fn allocateString(vm: *Vm, data: []const u8) !*Value.Object {
    const object = try vm.allocateObject(.string);
    object.data.string = .{ .bytes = data };
    try vm.strings.putNoClobber(data, object);
    return object;
}
pub fn allocateObject(vm: *Vm, tag: Value.Object.Tag) !*Value.Object {
    const object = try vm.objects.create(vm.gpa);
    object.tag = tag;
    object.next = vm.objects_head;
    vm.objects_head = object;
    return object;
}

pub const InterpretResult = enum { ok, compile_error, runtime_error };

pub fn interpret(vm: *Vm, source: [:0]const u8) !InterpretResult {
    if (try Compilation.compile(vm, source)) |index| {
        vm.setProto(index);
        return try vm.run();
    }
    return .compile_error;
}

fn run(vm: *Vm) !InterpretResult {
    while (true) {
        if (debug.TRACE_EXECUTION) {
            std.debug.print("          ", .{});
            for (0..vm.stack_top) |slot| {
                std.debug.print("[ {f} ]", .{vm.stack[slot]});
            }
            std.debug.print("\n", .{});

            _ = vm.proto.disassembleInstruction(vm.ip);
        }

        const op = vm.readOp();
        switch (op) {
            .pop => {
                _ = vm.pop();
            },
            .push_nil => vm.push(.nil),
            .push_true => vm.push(.true),
            .push_false => vm.push(.false),
            .push_constant => {
                const constant = vm.readConstant();
                vm.push(constant);
            },
            .bool_not => {
                vm.push(.fromBool(vm.pop().isFalsey()));
            },
            .negate => {
                if (!vm.peek(0).isNumber()) {
                    std.debug.print("tried to negate a non-number\n", .{});
                    return .runtime_error;
                }
                vm.push(.fromNumber(-vm.pop().asNumber()));
            },
            .cmp_eq => {
                const b = vm.pop();
                const a = vm.pop();
                vm.push(.fromBool(a.eql(b)));
            },
            .cmp_neq => {
                const b = vm.pop();
                const a = vm.pop();
                vm.push(.fromBool(!a.eql(b)));
            },
            .cmp_gt, .cmp_gte, .cmp_lt, .cmp_lte, .sub, .mul, .div => {
                if (!vm.peek(0).isNumber() or !vm.peek(1).isNumber()) {
                    std.debug.print("tried to do a numeric operation with non-numbers\n", .{});
                    return .runtime_error;
                }
                const b = vm.pop();
                const a = vm.pop();
                vm.push(switch (op) {
                    .cmp_gt => .fromBool(a.asNumber() > b.asNumber()),
                    .cmp_gte => .fromBool(a.asNumber() >= b.asNumber()),
                    .cmp_lt => .fromBool(a.asNumber() < b.asNumber()),
                    .cmp_lte => .fromBool(a.asNumber() <= b.asNumber()),
                    .add => .fromNumber(a.asNumber() + b.asNumber()),
                    .sub => .fromNumber(a.asNumber() - b.asNumber()),
                    .mul => .fromNumber(a.asNumber() * b.asNumber()),
                    .div => .fromNumber(a.asNumber() / b.asNumber()),
                    else => unreachable,
                });
            },
            .add => {
                if (vm.peek(0).isString() and vm.peek(1).isString()) {
                    const b = vm.pop();
                    const a = vm.pop();
                    const result = try std.mem.concat(vm.gpa, u8, &.{ a.asObject().data.string.bytes, b.asObject().data.string.bytes });
                    vm.push(.fromObject(try vm.takeString(result)));
                } else if (vm.peek(0).isNumber() and vm.peek(1).isNumber()) {
                    const b = vm.pop();
                    const a = vm.pop();
                    vm.push(.fromNumber(a.asNumber() + b.asNumber()));
                } else {
                    std.debug.print("addition is only allowed between two strings or two numbers\n", .{});
                    return .runtime_error;
                }
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

fn peek(vm: *Vm, offset: usize) Value {
    return vm.stack[vm.stack_top - 1 - offset];
}

fn readOp(vm: *Vm) Proto.OpCode {
    const op = vm.proto.code.items[vm.ip];
    vm.ip += 1;
    return op;
}

fn readByte(vm: *Vm) u8 {
    return @intFromEnum(vm.readOp());
}

fn readConstant(vm: *Vm) Value {
    return vm.proto.constants.items[vm.readByte()];
}
