const std = @import("std");
const Chunk = @import("Chunk");

chunk: Chunk.Chunk,

const Self = @This();

// initVM
pub fn init(chunk: *Chunk) Self {
    return Self{
        .chunk = chunk,
    };
}

// freeVM
pub fn deinit(self: Self) void {
    self.chunk.deinit();
}
