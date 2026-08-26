const std = @import("std");
const Io = std.Io;

const report = @import("report.zig");
const Source = @import("Source.zig");
const Vm = @import("Vm.zig");

const zettel = @import("zettel");

const usage = "usage: zettel [--error-format=rich|short] [script.zettel]";
const error_format_flag = "--error-format=";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    var script: ?[]const u8 = null;
    var style: ?report.Style = null;
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, error_format_flag)) {
            const name = arg[error_format_flag.len..];
            style = std.meta.stringToEnum(report.Style, name) orelse
                std.process.fatal("unknown error format '{s}', expected 'rich' or 'short'", .{name});
        } else if (script == null) {
            script = arg;
        } else {
            std.process.fatal("{s}", .{usage});
        }
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    defer stdout_writer.flush() catch {};

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;
    defer stderr_writer.flush() catch {};

    const color_mode = try Io.Terminal.Mode.detect(
        io,
        .stderr(),
        isSet(init.environ_map, "NO_COLOR"),
        isSet(init.environ_map, "CLICOLOR_FORCE"),
    );

    var vm: Vm = try .init(.{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .writer = stdout_writer,
        .diags = .{ .writer = stderr_writer, .mode = color_mode },
        .report_options = .{ .style = style orelse if (script == null) .short else .rich },
    });
    defer vm.deinit();

    if (script) |path| {
        const result = try runFile(&vm, path);
        if (result != .ok) {
            // `std.process.exit` doesn't call deferred statements.
            try stdout_writer.flush();
            try stderr_writer.flush();
            std.process.exit(switch (result) {
                .ok => unreachable,
                .compile_error => 65,
                .runtime_error => 70,
            });
        }
    } else {
        try repl(&vm);
    }
}

fn isSet(environ: *std.process.Environ.Map, name: []const u8) bool {
    const value = environ.get(name) orelse return false;
    return value.len > 0;
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

            var source: Source = try .init(vm.gpa, "<repl>", zeroDelimitedLine);
            defer source.deinit(vm.gpa);
            _ = try vm.interpret(&source);
        } else {
            try vm.writer.writeByte('\n');
            try vm.writer.flush();
            break;
        }
    }
}

fn runFile(vm: *Vm, path: []const u8) !Vm.InterpretResult {
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

    var source: Source = try .init(vm.gpa, path, file);
    defer source.deinit(vm.gpa);
    return vm.interpret(&source);
}
