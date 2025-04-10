const std = @import("std");
const Allocator = std.mem.Allocator;
const Chunk = @import("Chunk.zig");

pub const InterpretResult = enum(u8) {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub const STACK_MAX = 256;

allocator: Allocator,
chunk: *Chunk = undefined,
ip: usize = 0,
stack: [STACK_MAX]Chunk.Value = undefined,
stack_top: usize = 0,

const Self = @This();

// initVM
pub fn init(allocator: Allocator) Self {
    var vm = Self{
        .allocator = allocator,
    };
    vm.resetStack();
    return vm;
}

// freeVM
pub fn deinit(self: *Self) void {
    _ = self;
    // self.chunk.deinit();
}

pub fn interpret(self: *Self, chunk: *Chunk) InterpretResult {
    self.chunk = chunk;
    self.ip = 0;
    return self.run();
}

fn READ_BYTE(self: *Self) Chunk.OpCode {
    const byte: Chunk.OpCode = @enumFromInt(self.chunk.codes.items[self.ip]);
    self.ip += 1;
    return byte;
}

fn READ_CONSTANT(self: *Self) Chunk.Value {
    const index: u8 = self.chunk.codes.items[self.ip];
    self.ip += 1;
    const constant: Chunk.Value = self.chunk.constants.items[index];
    return constant;
}

fn run(self: *Self) InterpretResult {
    while (true) {
        if (Chunk.DEBUG_TRACE_EXECUTION) {
            std.debug.print("         ", .{});
            for (0..self.stack_top) |i| {
                std.debug.print("[ {d} ] ", .{self.stack[i]});
            }
            std.debug.print("\n", .{});
            std.debug.print("ip: {d}\n", .{self.ip});
            _ = self.chunk.dissembleInstruction(self.ip);
        }
        const instruction: Chunk.OpCode = self.READ_BYTE();
        switch (instruction) {
            .OP_CONSTANT => {
                const value = self.READ_CONSTANT();
                self.push(value) catch |err| {
                    std.debug.print("Error: {any}\n", .{err});
                    return .INTERPRET_RUNTIME_ERROR;
                };
            },
            .OP_NEGATE => {
                self.push(-self.pop()) catch |err| {
                    std.debug.print("Error: {any}\n", .{err});
                    return .INTERPRET_RUNTIME_ERROR;
                };
            },
            .OP_RETURN => {
                const value = self.pop();
                std.debug.print("OP_RETURN value: {d}\n", .{value});
                return .INTERPRET_OK;
            },
            else => return .INTERPRET_RUNTIME_ERROR,
        }
    }
}

fn resetStack(self: *Self) void {
    self.stack_top = 0;
}

fn push(self: *Self, value: Chunk.Value) !void {
    if (self.stack_top == STACK_MAX) {
        return error.StackOverflow;
    }
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

fn pop(self: *Self) Chunk.Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}
