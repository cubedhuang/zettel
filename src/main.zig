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
        std.process.fatal("usage: zettel [script.zettel]", .{});
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    defer stdout_writer.flush() catch {};

    var vm: Vm = try .init(.{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .writer = stdout_writer,
    });
    defer vm.deinit();

    if (args.len == 1) {
        try repl(&vm);
    } else {
        try runFile(&vm, args[1]);
    }
}

fn repl(vm: *Vm) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), vm.io, &stdin_buffer);
    const stdin_reader = &stdin_file_reader.interface;

    while (true) {
        try vm.writer.writeAll("> ");
        try vm.writer.flush();

        const maybeLine = try stdin_reader.takeDelimiter('\n');

        if (maybeLine) |line| {
            const zeroDelimitedLine = try vm.arena.dupeSentinel(u8, line, 0);
            _ = try vm.interpret(zeroDelimitedLine);
        } else {
            try vm.writer.writeByte('\n');
            try vm.writer.flush();
            break;
        }
    }
}

fn runFile(vm: *Vm, path: []const u8) !void {
    const file = std.Io.Dir.readFileAllocOptions(
        std.Io.Dir.cwd(),
        vm.io,
        path,
        vm.gpa,
        .limited(std.math.maxInt(u31) - 1),
        .of(u8),
        0,
    ) catch |err| {
        std.log.err("failed to open file: {s}", .{@errorName(err)});
        return err;
    };
    defer vm.gpa.free(file);

    _ = try vm.interpret(file);
}
