const std = @import("std");
const Zlox = @import("zlox_lib");
const VM = Zlox.VM;
const Chunk = Zlox.Chunk;
const OpCode = Zlox.OpCode;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = VM.init(allocator);
    defer vm.deinit();
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    try chunk.writeConstant(1.2, 123);
    try chunk.writeConstant(3.4, 123);
    try chunk.writeChunk(@intFromEnum(OpCode.OP_ADD), 123);

    try chunk.writeConstant(5.6, 123);
    try chunk.writeChunk(@intFromEnum(OpCode.OP_DIVIDE), 123);
    try chunk.writeChunk(@intFromEnum(OpCode.OP_NEGATE), 123);

    try chunk.writeChunk(@intFromEnum(OpCode.OP_RETURN), 125);
    try chunk.writeChunk(@intFromEnum(OpCode.OP_NOP), 129);

    chunk.disassembleChunk("test chunk");

    _ = vm.interpret(&chunk);

    return;
}
