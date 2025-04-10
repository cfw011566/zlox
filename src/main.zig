const std = @import("std");
const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const VM = @import("VM.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = VM.init(allocator);
    defer vm.deinit();
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    // const constant = try chunk.addConstant(1.2);
    // try chunk.writeChunk(@intFromEnum(OpCode.OP_CONSTANT), 123);
    // try chunk.writeChunk(@intCast(constant), 123);
    try chunk.writeConstant(1.2, 123);
    try chunk.writeChunk(@intFromEnum(OpCode.OP_NEGATE), 123);

    try chunk.writeChunk(@intFromEnum(OpCode.OP_RETURN), 125);
    try chunk.writeChunk(@intFromEnum(OpCode.OP_NOP), 129);

    chunk.disassembleChunk("test chunk");

    _ = vm.interpret(&chunk);

    return;
}
