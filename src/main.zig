const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const log = std.log;

const assert = std.debug.assert;

/// Logger(.main)
const ml = log.scoped(.main);

const Token = struct {
    line: u64 = 0,
    linec: u64 = 0,
    /// must be freed
    data: []u8 = undefined,
};

fn readFile(allocator: mem.Allocator, filename: []const u8) ![]u8 {
    // read file
    const current_dir = fs.cwd();
    const file = try fs.Dir.openFile(current_dir, filename, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    return try file.readToEndAlloc(allocator, file_size);
}

// naive tokenizer
fn tokenize(allocator: mem.Allocator, source_code: []const u8) !std.ArrayList(Token) {

    // no need to free bc arena allocator
    var token_list = std.ArrayList(Token).init(allocator);

    var slice_start: ?u64 = null;
    var line: u64 = 0;
    var linec: u64 = 0;

    for (source_code, 0..) |c, i| {
        switch (c) {
            // zig fmt: off
                ' ', '\t', '\n',
                ':', '=', '&', '@', '$', '{', '}', '(', ')', ';' => {
                // zig fmt: on
                if (c == '\n') {
                    line += 1;
                    linec = 0;
                } else linec += 1;

                if (slice_start) |s_start| {
                    const s_end = i;
                    try token_list.append(.{
                        .line = line,
                        .linec = linec,
                        .data = try allocator.dupe(u8, source_code[s_start..s_end]),
                    });

                    slice_start = null;
                }
                // else ml.debug("empty slice start at line: {}:{}", .{ line, linec });

                // in case of the special symbols here, they are also
                // tokens and need to be appended accordingly
                // zig fmt: off
                    if (c == ':' or c == '=' or c == '&' or
                        c == '@' or c == '$' or c == '{' or
                        c == '}' or c == '(' or c == ')' or c == ';') {
                    // zig fmt: on
                    try token_list.append(.{
                        .line = line,
                        .linec = linec,
                        .data = try allocator.dupe(u8, source_code[i .. i + 1]),
                    });
                }
            },
            else => {
                if (slice_start == null) {
                    slice_start = i;
                }
            },
        }
    }

    return token_list;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer if (gpa.detectLeaks()) @panic("memory leak found!");

    var arena_alloc = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    // no need to free bc arena allocator
    const source_code = try readFile(allocator, "test");
    const tokens = try tokenize(allocator, source_code);

    for (tokens.items) |item| {
        ml.debug("found: \"{s}\"", .{item.data});
    }
    ml.debug("------------------------------", .{});
}
