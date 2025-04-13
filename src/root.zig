const std = @import("std");
const Allocator = std.mem.Allocator;

// Chunk.zig

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

pub const Chunk = struct {
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
};

// VM.zig

pub const InterpretResult = enum(u8) {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub const STACK_MAX = 256;

pub const VM = struct {
    allocator: Allocator,
    is_debug: bool = false,
    chunk: *Chunk = undefined,
    ip: usize = 0,
    stack: [STACK_MAX]Value = undefined,
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

    inline fn READ_BYTE(self: *Self) u8 {
        const byte = self.chunk.codes.items[self.ip];
        self.ip += 1;
        return byte;
    }

    inline fn READ_CONSTANT(self: *Self) Value {
        return self.chunk.constants.items[self.READ_BYTE()];
    }

    fn run(self: *Self) InterpretResult {
        while (true) {
            if (self.is_debug) {
                std.debug.print("         ", .{});
                for (0..self.stack_top) |i| {
                    std.debug.print("[ {d} ] ", .{self.stack[i]});
                }
                std.debug.print("\n", .{});
                _ = self.chunk.dissembleInstruction(self.ip);
            }
            const instruction: OpCode = @enumFromInt(self.READ_BYTE());
            switch (instruction) {
                .OP_CONSTANT => {
                    const value = self.READ_CONSTANT();
                    self.push(value) catch |err| {
                        std.debug.print("Error: {any}\n", .{err});
                        return .INTERPRET_RUNTIME_ERROR;
                    };
                },
                .OP_ADD => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a + b) catch |err| {
                        std.debug.print("Error: {any}\n", .{err});
                        return .INTERPRET_RUNTIME_ERROR;
                    };
                },
                .OP_SUBTRACT => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a - b) catch |err| {
                        std.debug.print("Error: {any}\n", .{err});
                        return .INTERPRET_RUNTIME_ERROR;
                    };
                },
                .OP_MULTIPLY => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(a * b) catch |err| {
                        std.debug.print("Error: {any}\n", .{err});
                        return .INTERPRET_RUNTIME_ERROR;
                    };
                },
                .OP_DIVIDE => {
                    const b = self.pop();
                    const a = self.pop();
                    if (b == 0) {
                        return .INTERPRET_RUNTIME_ERROR;
                    }
                    self.push(a / b) catch |err| {
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

    fn push(self: *Self, value: Value) !void {
        if (self.stack_top == STACK_MAX) {
            return error.StackOverflow;
        }
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    fn pop(self: *Self) Value {
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }
};

// Scanner.zig

pub const Token = struct {
    token_type: TokenType,
    token_string: []const u8,
    line: usize,
};

const TokenType = enum(u8) {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,

    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,

    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,

    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FUN,
    FOR,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    ERROR,
    EOF,
};

pub const Scanner = struct {
    source: []const u8,
    start: usize,
    current: usize,
    line: usize,

    const Self = @This();

    pub fn init(source: []const u8) Self {
        return Self{
            .source = source,
            .start = 0,
            .current = 0,
            .line = 1,
        };
    }

    pub fn scanToken() Token {
        scanner.start = scanner.current;

        if (isAtEnd()) {
            return makeToken(.EOF);
        }

        return errorToken("Unexpected character.");
    }

    fn isAtEnd() bool {
        return scanner.current >= scanner.source.len;
    }

    fn makeToken(token_type: TokenType) Token {
        return Token{
            .token_type = token_type,
            .token_string = scanner.source[scanner.start..scanner.current],
            .line = scanner.line,
        };
    }

    fn errorToken(message: []const u8) Token {
        return Token{
            .token_type = .ERROR,
            .token_string = message,
            .line = scanner.line,
        };
    }
};

// Compiler.zig

const scanner = undefined;

pub fn compile(source: []const u8) void {
    scanner = Scanner.initScanner(source);
    var line = 0;
    while (true) {
        const token = scanner.scanToken();
        if (token.line != line) {
            std.debug.print("%4d ", token.line);
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        const token_str = source[token.start .. token.start + token.length];
        std.debug.print("{d:2} '{s}'\n", .{ token.type, token_str });

        if (token.type == .TOKEN_EOF) {
            break;
        }
    }
}
