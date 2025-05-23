const std = @import("std");

pub const DEBUG_TRACE_EXECUTION = true;

pub const Value = f64;

pub const OpCode = enum(u8) {
    OP_UNKNOWN,
    OP_NOP,
    OP_CONSTANT,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NEGATE,
    OP_CONSTANT_LONG,
    OP_RETURN,
};

allocator: std.mem.Allocator,
codes: std.ArrayList(u8),
lines: std.ArrayList(usize),
constants: std.ArrayList(Value),

const Self = @This();

// initChunk
pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .codes = std.ArrayList(u8).init(allocator),
        .lines = std.ArrayList(usize).init(allocator),
        .constants = std.ArrayList(Value).init(allocator),
    };
}

// freeChunk
pub fn deinit(self: *Self) void {
    self.codes.deinit();
    self.lines.deinit();
    self.constants.deinit();
}

pub fn writeChunk(self: *Self, byte: u8, line: usize) !void {
    try self.codes.append(byte);
    try self.lines.append(line);
}

pub fn writeConstant(self: *Self, value: Value, line: usize) !void {
    const index = try self.addConstant(value);
    if (index <= 255) {
        try self.writeChunk(@intFromEnum(OpCode.OP_CONSTANT), line);
        try self.writeChunk(@intCast(index), line);
    } else {
        try self.writeChunk(@intFromEnum(OpCode.OP_CONSTANT_LONG), line);
        var byte = index & 0xFF;
        try self.writeChunk(@intCast(byte), line);
        byte = (index >> 8) & 0xFF;
        try self.writeChunk(@intCast(byte), line);
        byte = (index >> 16) & 0xFF;
        try self.writeChunk(@intCast(byte), line);
    }
}

pub fn addConstant(self: *Self, value: Value) !usize {
    try self.constants.append(value);
    return self.constants.items.len - 1;
}

pub fn disassembleChunk(self: Self, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < self.codes.items.len) {
        offset = self.dissembleInstruction(offset);
    }
    std.debug.print("== {s} ==\n", .{name});
}

pub fn dissembleInstruction(self: Self, offset: usize) usize {
    std.debug.print("{d:04} ", .{offset});
    if (offset > 0 and self.lines.items[offset] == self.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{self.lines.items[offset]});
    }

    const instruction: OpCode = @enumFromInt(self.codes.items[offset]);
    switch (instruction) {
        .OP_CONSTANT => return self.constantInstruction("OP_CONSTANT", offset),
        .OP_ADD => return self.simpleInstruction("OP_ADD", offset),
        .OP_SUBTRACT => return self.simpleInstruction("OP_SUBTRACT", offset),
        .OP_MULTIPLY => return self.simpleInstruction("OP_MULTIPLY", offset),
        .OP_DIVIDE => return self.simpleInstruction("OP_DIVIDE", offset),
        .OP_NEGATE => return self.simpleInstruction("OP_NEGATE", offset),
        .OP_CONSTANT_LONG => return self.constantLongInstruction("OP_CONSTANT_LONG", offset),
        .OP_RETURN => return self.simpleInstruction("OP_RETURN", offset),
        .OP_NOP => return self.simpleInstruction("OP_NOP", offset),
        else => {
            std.debug.print("Unknown opcode {}\n", .{instruction});
            return offset + 1;
        },
    }
}

fn simpleInstruction(self: Self, name: []const u8, offset: usize) usize {
    _ = self;
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn constantInstruction(self: Self, name: []const u8, offset: usize) usize {
    const index = self.codes.items[offset + 1];
    const constant = self.constants.items[index];
    std.debug.print("{s:<16} {d:4} '{d}'\n", .{ name, index, constant });
    return offset + 2;
}

fn constantLongInstruction(self: Self, name: []const u8, offset: usize) usize {
    var index: usize = self.codes.items[offset + 3];
    index <<= 8;
    index += self.codes.items[offset + 2];
    index <<= 8;
    index += self.codes.items[offset + 1];
    const constant = self.constants.items[index];
    std.debug.print("{s:<16} {d:4} '{d}'\n", .{ name, index, constant });
    return offset + 4;
}

fn printValue(value: Value) void {
    std.debug.print("{d}\n", .{value});
}
