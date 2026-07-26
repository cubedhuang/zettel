const std = @import("std");
const Io = std.Io;

const Chunk = @import("Chunk.zig");
const Vm = @import("Vm.zig");

const zettel = @import("zettel");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 2) {
        std.log.err("usage: zettel [script.zettel]", .{});
        return error.InvalidUsage;
    }

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const file = std.Io.Dir.readFileAlloc(
        std.Io.Dir.cwd(),
        io,
        args[1],
        arena,
        .limited(std.math.maxInt(u31) - 1),
    ) catch |err| {
        std.log.err("failed to open file: {s}", .{@errorName(err)});
        return err;
    };
    _ = file;

    var vm: Vm = try .init(.{
        .gpa = gpa,
        .io = io,
        .writer = stdout_writer,
    });
    defer vm.deinit();

    var chunk: Chunk = .empty;
    defer chunk.deinit(gpa);

    var index = try chunk.addConstant(gpa, .{ .data = 1.2 });
    try chunk.write(gpa, .constant, 123);
    try chunk.writeByte(gpa, @intCast(index), 123);

    index = try chunk.addConstant(gpa, .{ .data = 3.4 });
    try chunk.write(gpa, .constant, 123);
    try chunk.writeByte(gpa, @intCast(index), 123);

    try chunk.write(gpa, .add, 123);

    index = try chunk.addConstant(gpa, .{ .data = 5.6 });
    try chunk.write(gpa, .constant, 123);
    try chunk.writeByte(gpa, @intCast(index), 123);

    try chunk.write(gpa, .div, 123);
    try chunk.write(gpa, .negate, 123);

    try chunk.write(gpa, .ret, 123);
    chunk.disassemble("test chunk");

    const result = try vm.interpret(&chunk);
    std.debug.print("output: {}\n", .{result});

    try stdout_writer.flush();
}
