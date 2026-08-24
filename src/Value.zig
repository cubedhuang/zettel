const std = @import("std");
const Allocator = std.mem.Allocator;

const SIGN_BIT: u64 = 0x8000000000000000;
const QNAN: u64 = 0x7ffc000000000000;

const TAG_NIL = 1;
const TAG_TRUE = 2;
const TAG_FALSE = 3;

pub const nil = Value{ .data = QNAN | TAG_NIL };
pub const @"true" = Value{ .data = QNAN | TAG_TRUE };
pub const @"false" = Value{ .data = QNAN | TAG_FALSE };

const Value = @This();

data: u64,

pub fn isNumber(value: Value) bool {
    return value.data & QNAN != QNAN;
}
pub fn fromNumber(number: f64) Value {
    return .{ .data = @bitCast(number) };
}
pub fn asNumber(value: Value) f64 {
    return @bitCast(value.data);
}

pub fn isNil(value: Value) bool {
    return value.data == Value.nil.data;
}

pub fn isBool(value: Value) bool {
    return value.data | 1 == Value.false.data;
}
pub fn fromBool(value: bool) Value {
    return .{ .data = if (value) Value.true.data else Value.false.data };
}
pub fn asBool(value: Value) bool {
    return value.data == Value.true.data;
}

pub fn isObject(value: Value) bool {
    return (value.data & (QNAN | SIGN_BIT)) == (QNAN | SIGN_BIT);
}
pub fn fromObject(object: *Object) Value {
    return .{ .data = SIGN_BIT | QNAN | @intFromPtr(object) };
}
pub fn asObject(value: Value) *Object {
    return @ptrFromInt((value.data & ~(SIGN_BIT | QNAN)));
}

pub fn isString(value: Value) bool {
    return value.isObject() and value.asObject().tag == .string;
}

pub fn eql(a: Value, b: Value) bool {
    return a.data == b.data;
}
pub fn isFalsey(value: Value) bool {
    return value.isNil() or (value.isBool() and !value.asBool());
}

pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    if (self.isNumber()) {
        try writer.print("{d}", .{self.asNumber()});
    } else if (self.isBool()) {
        try writer.writeAll(if (self.asBool()) "true" else "false");
    } else if (self.isNil()) {
        try writer.writeAll("nil");
    } else if (self.isObject()) {
        try self.asObject().format(writer);
    } else {
        try writer.writeAll("<invalid Value>");
    }
}

pub const Object = struct {
    tag: Tag,
    next: ?*Object,
    data: Data,

    pub const Tag = enum {
        string,
        record,
    };

    pub const Data = union {
        string: String,
        record: Record,
    };

    pub const String = struct {
        bytes: []const u8,
    };

    pub const Record = struct {
        map: std.array_hash_map.Auto(u64, Value),
    };

    pub fn freeData(object: *Object, gpa: Allocator) void {
        switch (object.tag) {
            .string => gpa.free(object.data.string.bytes),
            .record => object.data.record.map.deinit(gpa),
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self.tag) {
            .string => try writer.print("\"{s}\"", .{self.data.string.bytes}),
            .record => {
                try writer.writeAll("[ ");
                const map = &self.data.record.map;
                var iterator = map.iterator();
                var first = true;
                while (iterator.next()) |entry| {
                    if (first) {
                        first = false;
                    } else {
                        try writer.writeAll(", ");
                    }
                    const key: Value = .{ .data = entry.key_ptr.* };
                    const value = entry.value_ptr.*;
                    try writer.print("{f} = {f}", .{ key, value });
                }
                try writer.writeAll(" ]");
            },
        }
    }
};
