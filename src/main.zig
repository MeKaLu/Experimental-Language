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

const Keywords = enum {
    let,
    discard,
};

const StatementType = enum {
    lhand,
    lhand_identifier,
    mhand,
    mhand_identifier,
    meqhand,
    rhand,

    done,
};

const Statement = union(StatementType) {
    lhand: ?[]u8,
    lhand_identifier: ?[]u8,
    mhand: ?[]u8,
    mhand_identifier: ?[]u8,
    meqhand: ?[]u8,
    rhand: ?[]u8,

    done: ?[]u8,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer if (gpa.detectLeaks()) @panic("memory leak found!");
    const allocator = gpa.allocator();

    const current_dir = fs.cwd();
    const file = try fs.Dir.openFile(current_dir, "test", .{});
    const file_size = try file.getEndPos();
    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    var token_list = std.ArrayList(Token).init(allocator);
    defer {
        for (token_list.items) |item| {
            allocator.free(item.data);
        }
        token_list.deinit();
    }

    // Split the tokens by space
    {
        var slice_start: ?u64 = null;
        var line: u64 = 0;
        var linec: u64 = 0;

        for (file_buffer, 0..) |c, i| {
            switch (c) {
                ' ', ':', '=', '&', ';', '\t', '\n' => {
                    if (c == '\n') {
                        line += 1;
                        linec = 0;
                    } else linec += 1;

                    if (slice_start) |s_start| {
                        const s_end = i;
                        try token_list.append(.{
                            .line = line,
                            .linec = linec,
                            .data = try allocator.dupe(u8, file_buffer[s_start..s_end]),
                        });

                        // ml.info("token = \"{s}\"`", .{file_buffer[s_start..s_end]});
                        // ml.debug("should end", .{});
                        slice_start = null;
                    } else ml.debug("empty slice start at line: {}:{}", .{ line, linec });

                    if (c == ':' or c == '=' or c == '&' or c == ';') {
                        try token_list.append(.{
                            .line = line,
                            .linec = linec,
                            .data = try allocator.dupe(u8, file_buffer[i .. i + 1]),
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
    }

    for (token_list.items) |item| {
        ml.debug("found: \"{s}\"", .{item.data});
    }
    ml.debug("------------------------------", .{});

    // parse the tokens
    {
        // TODO make them copy not just ptr
        var statements = std.ArrayList(Statement).init(allocator);
        defer statements.deinit();

        var state = StatementType.lhand;
        var statement_recurse: u64 = 0;
        for (token_list.items) |item| {
            sw: switch (state) {
                .lhand => {
                    // TODO
                    // backpatch recursive expressions
                    // or find a way to do it without backpatch
                    if (mem.eql(u8, item.data, "let")) {
                        statement_recurse += 1;
                        try statements.append(.{ .lhand = item.data });
                        state = .lhand_identifier;
                    } else if (mem.eql(u8, item.data, "discard")) {
                        // in case of discard, there is no identifier,
                        // so we skip that step
                        statement_recurse += 1;
                        try statements.append(.{ .lhand = item.data });
                        state = .mhand;
                    } else {
                        if (statement_recurse == 1) {
                            continue :sw .done;
                        } else @panic("unknown keyword!");
                        // ml.err("unknown keyword = \"{s}\"", .{item.data});
                    }
                },
                .lhand_identifier => {
                    // TODO verify the identifier
                    if (mem.eql(u8, item.data, "mut")) {
                        // mutable
                        try statements.append(.{ .lhand_identifier = item.data });
                    } else {
                        // identifier
                        try statements.append(.{ .lhand_identifier = item.data });
                        state = .mhand;
                    }
                },
                .mhand => {
                    // verify operand
                    if (mem.eql(u8, item.data, ":")) {
                        try statements.append(.{ .mhand = item.data });
                        state = .mhand_identifier;
                    } else @panic("unknown mhand operand!");
                },
                .mhand_identifier => {
                    // TODO verify ident
                    // do not append if it is =
                    // otherwise keep appending
                    if (mem.eql(u8, item.data, "=")) {
                        state = .meqhand;
                        continue :sw .meqhand;
                    } else {
                        try statements.append(.{ .mhand_identifier = item.data });
                    }
                },
                .meqhand => {
                    // verify operand
                    if (mem.eql(u8, item.data, "=")) {
                        try statements.append(.{ .meqhand = item.data });
                        state = .rhand;
                    } else @panic("unknown meqhand operand!");
                },
                .rhand => {
                    // TODO
                    if (mem.eql(u8, item.data, "let") or mem.eql(u8, item.data, "discard")) {
                        continue :sw .lhand;
                    } else if (mem.eql(u8, item.data, ";")) {
                        if (statement_recurse > 0) statement_recurse -= 1;
                        continue :sw .done;
                    } else {
                        if (statement_recurse > 0) {
                            try statements.append(.{ .rhand = item.data });
                        }
                    }
                },
                .done => {
                    try statements.append(.{ .done = item.data });
                    state = .lhand;
                },
                // else => ml.warn("{s} is not implemented!", .{@tagName(state)}),
            }
        }

        for (statements.items) |item| {
            switch (item) {
                .lhand => |capture| ml.debug("lhand = \"{s}\"", .{capture orelse "null"}),
                .lhand_identifier => |capture| ml.debug("lhand_identifier = \"{s}\"", .{capture orelse "null"}),
                .mhand => |capture| ml.debug("mhand = \"{s}\"", .{capture orelse "null"}),
                .mhand_identifier => |capture| ml.debug("mhand_identifier = \"{s}\"", .{capture orelse "null"}),
                .meqhand => |capture| ml.debug("meqhand = \"{s}\"", .{capture orelse "null"}),
                .rhand => |capture| ml.debug("rhand = \"{s}\"", .{capture orelse "null"}),
                .done => |capture| ml.debug("done = \"{s}\"", .{capture orelse "null"}),
            }
        }
    }
}
