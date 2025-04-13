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
    allocator: Allocator,
    codes: std.ArrayList(u8),
    lines: std.ArrayList(usize),
    constants: std.ArrayList(Value),

    const Self = @This();

    // initChunk
    pub fn init(allocator: Allocator) Self {
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
        return switch (instruction) {
            .OP_CONSTANT => self.constantInstruction("OP_CONSTANT", offset),
            .OP_ADD => self.simpleInstruction("OP_ADD", offset),
            .OP_SUBTRACT => self.simpleInstruction("OP_SUBTRACT", offset),
            .OP_MULTIPLY => self.simpleInstruction("OP_MULTIPLY", offset),
            .OP_DIVIDE => self.simpleInstruction("OP_DIVIDE", offset),
            .OP_NEGATE => self.simpleInstruction("OP_NEGATE", offset),
            .OP_CONSTANT_LONG => self.constantLongInstruction("OP_CONSTANT_LONG", offset),
            .OP_RETURN => self.simpleInstruction("OP_RETURN", offset),
            .OP_NOP => self.simpleInstruction("OP_NOP", offset),
            else => blk: {
                std.debug.print("Unknown opcode {}\n", .{instruction});
                break :blk offset + 1;
            },
        };
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

    pub fn interpret(self: *Self, source: []const u8) InterpretResult {
        _ = self;
        compile(source);
        return .INTERPRET_OK;
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

    pub fn scanToken(self: *Self) Token {
        self.skipWhiteSpace();

        scanner.start = scanner.current;

        if (self.isAtEnd()) return self.makeToken(.EOF);

        const c: u8 = self.advance();
        if (isAlpha(c)) return self.identifier();
        if (isDigit(c)) return self.number();

        return switch (c) {
            '(' => self.makeToken(.LEFT_PAREN),
            ')' => self.makeToken(.RIGHT_PAREN),
            '{' => self.makeToken(.LEFT_BRACE),
            '}' => self.makeToken(.RIGHT_BRACE),
            ';' => self.makeToken(.SEMICOLON),
            ',' => self.makeToken(.COMMA),
            '.' => self.makeToken(.DOT),
            '-' => self.makeToken(.MINUS),
            '+' => self.makeToken(.PLUS),
            '/' => self.makeToken(.SLASH),
            '*' => self.makeToken(.STAR),
            '!' => if (self.match('=')) self.makeToken(.BANG_EQUAL) else self.makeToken(.BANG),
            '=' => if (self.match('=')) self.makeToken(.EQUAL_EQUAL) else self.makeToken(.EQUAL),
            '<' => if (self.match('=')) self.makeToken(.LESS_EQUAL) else self.makeToken(.LESS),
            '>' => if (self.match('=')) self.makeToken(.GREATER_EQUAL) else self.makeToken(.GREATER),
            '"' => self.string(),
            else => self.errorToken("Unexpected character."),
        };
    }

    fn isAtEnd(self: Self) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Self) u8 {
        const c = self.source[self.current];
        self.current += 1;
        return c;
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;

        self.current += 1;
        return true;
    }

    fn makeToken(self: Self, token_type: TokenType) Token {
        return Token{
            .token_type = token_type,
            .token_string = self.source[self.start..self.current],
            .line = self.line,
        };
    }

    fn errorToken(self: Self, message: []const u8) Token {
        return Token{
            .token_type = .ERROR,
            .token_string = message,
            .line = self.line,
        };
    }

    fn skipWhiteSpace(self: *Self) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n' and !self.isAtEnd())
                            _ = self.advance();
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn identifierType(self: Self) TokenType {
        const c = self.source[self.start];
        return switch (c) {
            'a' => self.checkKeyword(1, 2, "nd", .AND),
            'c' => self.checkKeyword(1, 4, "lass", .CLASS),
            'e' => self.checkKeyword(1, 3, "else", .ELSE),
            'f' => blk: {
                const second = self.source[self.start + 1];
                break :blk switch (second) {
                    'a' => self.checkKeyword(2, 3, "lse", .FALSE),
                    'o' => self.checkKeyword(2, 1, "r", .FOR),
                    'u' => self.checkKeyword(2, 2, "n", .FUN),
                    else => .IDENTIFIER,
                };
            },
            'i' => self.checkKeyword(1, 1, "f", .IF),
            'n' => self.checkKeyword(1, 2, "il", .NIL),
            'o' => self.checkKeyword(1, 1, "r", .OR),
            'p' => self.checkKeyword(1, 4, "rint", .PRINT),
            'r' => self.checkKeyword(1, 5, "eturn", .RETURN),
            's' => self.checkKeyword(1, 4, "uper", .SUPER),
            't' => blk: {
                const second = self.source[self.start + 1];
                break :blk switch (second) {
                    'h' => self.checkKeyword(2, 2, "is", .THIS),
                    'r' => self.checkKeyword(2, 2, "ue", .TRUE),
                    else => .IDENTIFIER,
                };
            },
            'v' => self.checkKeyword(1, 2, "ar", .VAR),
            'w' => self.checkKeyword(1, 4, "hile", .WHILE),
            else => .IDENTIFIER,
        };
    }

    fn checkKeyword(
        self: Self,
        start: usize,
        length: usize,
        rest: []const u8,
        token_type: TokenType,
    ) TokenType {
        if (self.current - self.start == length) {
            const begin = self.start + start;
            const end = begin + length;
            if (std.mem.eql(u8, self.source[begin..end], rest))
                return token_type;
        }
        return .IDENTIFIER;
    }

    fn string(self: *Self) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.isAtEnd()) return self.errorToken("Unterminated string.");

        // The closing quote.
        _ = self.advance();
        return self.makeToken(.STRING);
    }

    fn number(self: *Self) Token {
        while (isDigit(self.peek())) _ = self.advance();

        // Look for a fractional part
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            // Consume '.'
            _ = self.advance();

            while (isDigit(self.peek())) _ = self.advance();
        }

        return self.makeToken(.NUMBER);
    }

    fn identifier(self: *Self) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();

        return self.makeToken(self.identifierType());
    }

    fn peek(self: Self) u8 {
        return if (self.isAtEnd()) 0 else self.source[self.current];
    }

    fn peekNext(self: Self) u8 {
        return if (self.isAtEnd()) 0 else self.source[self.current + 1];
    }

    fn isAlpha(c: u8) bool {
        return ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_');
    }

    fn isDigit(c: u8) bool {
        return (c >= '0' and c <= '9');
    }
};

// Compiler.zig

var scanner: Scanner = undefined;

pub fn compile(source: []const u8) void {
    scanner = Scanner.init(source);
    var line: usize = 0;
    while (true) {
        const token = scanner.scanToken();
        if (token.line != line) {
            std.debug.print("{d:4} ", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{d:2} '{s}'\n", .{ @intFromEnum(token.token_type), token.token_string });

        if (token.token_type == .EOF or token.token_type == .ERROR) {
            break;
        }
    }
}
