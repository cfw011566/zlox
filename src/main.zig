const std = @import("std");
const Zlox = @import("zlox_lib");
const VM = Zlox.VM;
const Chunk = Zlox.Chunk;
const OpCode = Zlox.OpCode;
const InterpretResult = Zlox.InterpretResult;

var vm: VM = undefined;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    vm = VM.init(allocator);
    defer vm.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        try repl();
    } else if (args.len == 2) {
        runFile(args[1]);
    } else {
        std.debug.print("Usage: zjlox [script]\n", .{});
        std.process.exit(64);
    }

    return;
}

fn repl() !void {
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    var buffer: [1024]u8 = undefined;
    while (true) {
        try stdout.writeAll("> ");
        const line = try stdin.reader().readUntilDelimiterOrEof(&buffer, '\n');
        if (line == null or line.?.len == 0) {
            break;
        }
        _ = vm.interpret(line.?);
    }
}

fn runFile(path: []const u8) void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Could not open file: {any}\n", .{err});
        return;
    };
    defer file.close();

    const source = file.readToEndAlloc(std.heap.page_allocator, 8192) catch |err| {
        std.debug.print("Could not read file: {any}\n", .{err});
        return;
    };
    defer std.heap.page_allocator.free(source);

    const result = vm.interpret(source);

    if (result == .INTERPRET_COMPILE_ERROR) std.process.exit(65);
    if (result == .INTERPRET_RUNTIME_ERROR) std.process.exit(70);
}
