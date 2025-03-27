const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const log = std.log;

const assert = std.debug.assert;

/// Logger(.main).
const ml = log.scoped(.main);

const SymbolError = error{
    Unknown,
};

const SymbolTag = enum {
    /// if null, it can be any of the ident tags.
    fn totag(string: []const u8) ?SymbolTag {
        if (mem.eql(u8, "discard", string)) { // Statements:
            return .st_discard;
        } else if (mem.eql(u8, "let", string)) {
            return .st_let;
        } else if (mem.eql(u8, "mut", string)) {
            return .st_mut;
        } else if (mem.eql(u8, ":", string)) {
            return .st_type;
        } else if (mem.eql(u8, "=", string)) {
            return .st_eq;
        } else if (mem.eql(u8, ";", string)) {
            return .st_semicolon;
        } else if (mem.eql(u8, "@", string)) { // Expressions:
            return .exp_compiler;
        } else if (mem.eql(u8, "true", string)) {
            return .exp_true;
        } else if (mem.eql(u8, "false", string)) {
            return .exp_false;
        } else if (mem.eql(u8, "(", string)) { // Ops:
            return .op_lparan;
        } else if (mem.eql(u8, ")", string)) {
            return .op_rparan;
        } else if (mem.eql(u8, "{", string)) {
            return .op_lcbracket;
        } else if (mem.eql(u8, "}", string)) {
            return .op_rcbracket;
        } else if (mem.eql(u8, "[", string)) {
            return .op_lsbracket;
        } else if (mem.eql(u8, "]", string)) {
            return .op_rsbracket;
        } else return null; // Ident:
    }

    ident,

    st_discard,
    st_let,
    st_mut,
    st_type,
    st_eq,
    st_semicolon,

    exp_compiler,
    exp_true,
    exp_false,

    op_lparan,
    op_rparan,
    op_lcbracket,
    op_rcbracket,
    op_lsbracket,
    op_rsbracket,
};

const Symbol = struct {
    tag: SymbolTag,
    token: Token,

    /// null is fail.
    fn expect(self: Symbol, tag: SymbolTag) ?SymbolTag {
        return if (self.tag == tag) tag else null;
    }

    /// null is fail.
    fn expectEither(self: Symbol, tag: []const SymbolTag) ?SymbolTag {
        for (tag) |t| {
            if (self.tag == t) return t;
        }
        return null;
    }
};

const Token = struct {
    line: u64 = 0,
    linec: u64 = 0,
    /// must be freed
    data: []u8 = undefined,

    fn toSymbol(self: Token) Symbol {
        const tag = SymbolTag.totag(self.data) orelse .ident;
        return .{ .tag = tag, .token = self };
    }
};

/// Caller owns the memory.
fn readFile(allocator: mem.Allocator, filename: []const u8) ![]u8 {
    const current_dir = fs.cwd();
    const file = try fs.Dir.openFile(current_dir, filename, .{});
    defer file.close();
    const file_size = try file.getEndPos();
    return try file.readToEndAlloc(allocator, file_size);
}

/// Caller owns the memory.
/// This does clone the memory, each individual item should be free'd as well.
/// After this source_code is no longer needed for tokens.
fn tokenize(allocator: mem.Allocator, source_code: []const u8) !std.ArrayList(Token) {
    var token_list = std.ArrayList(Token).init(allocator);

    var slice_start: ?u64 = null;
    var line: u64 = 1;
    var linec: u64 = 0;

    for (source_code, 0..) |c, i| {
        switch (c) {
            // zig fmt: off
            ' ', '\t', '\n',
            ':', '=', '&', '@', '$', ';' ,
            '[', ']', '{', '}', '(', ')' => {
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
                // tokens and need to be appended accordingly.
                // zig fmt: off
                if (i + 1 < source_code.len and (
                        c == ':' or c == '=' or c == '&' or c == ';' or
                        c == '@' or c == '$' or c == '[' or c == ']' or
                        c == '{' or c == '}' or c == '(' or c == ')')) {
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

/// Caller owns the memory.
fn symbolize(allocator: mem.Allocator, tokens: []const Token) !std.ArrayList(Symbol) {
    var symbols = std.ArrayList(Symbol).init(allocator);
    for (tokens) |token| {
        try symbols.append(token.toSymbol());
    }
    return symbols;
}

fn compileError(msg: []const u8) noreturn {
    @panic(msg);
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer if (gpa.detectLeaks()) @panic("memory leak found!");

    // Making sure we are not forgetting all of these here uses arena allocator.
    arena_alloc_blk: {
        var arena_alloc = std.heap.ArenaAllocator.init(gpa.allocator());
        defer arena_alloc.deinit();
        const allocator = arena_alloc.allocator();

        // no need to free bc arena allocator.
        const source_code = try readFile(allocator, "test");
        const tokens = try tokenize(allocator, source_code);
        const symbols = try symbolize(allocator, tokens.items);

        for (tokens.items) |item| {
            ml.debug("token found: \"{s}\"", .{item.data});
        }
        ml.debug("------------------------------", .{});

        for (symbols.items) |item| {
            ml.debug("symbol found: {s} = \"{s}\"", .{ @tagName(item.tag), item.token.data });
        }
        ml.debug("------------------------------", .{});

        var i: usize = 0;
        const syms = symbols.items;

        // Find all identifiers:
        while (i < syms.len) : (i += 1) {
            _ = syms[i].expect(.st_let) orelse continue;
            i += 1;
            const r = syms[i].expectEither(&.{ .ident, .st_mut }) orelse continue;
            if (r == .st_mut) {
                i += 1;
                _ = syms[i].expect(.ident) orelse continue;

                ml.info("Found [let mut] with identifier => {s}", .{syms[i].token.data});
                continue;
            }
            ml.info("Found [let] with identifier => {s}", .{syms[i].token.data});
        }

        i = 0;
        // Find all discard's:
        while (i < syms.len) : (i += 1) {
            _ = syms[i].expect(.st_discard) orelse continue;
            const discard_i = i;
            i += 1;
            _ = syms[i].expect(.st_type) orelse continue;
            i += 1;
            _ = syms[i].expect(.st_eq) orelse continue;

            ml.info("Found [discard] at {}:{} ", .{ syms[discard_i].token.line, syms[discard_i].token.linec });
        }

        i = 0;
        // Find all compiler expressions:
        while (i < syms.len) : (i += 1) {
            _ = syms[i].expect(.exp_compiler) orelse continue;
            i += 1;
            if (syms[i].expect(.op_lparan) != null) {
                i += 1;
                const ident = syms[i];
                _ = syms[i].expect(.ident) orelse continue;
                i += 1;
                _ = syms[i].expect(.st_eq) orelse continue;
                i += 1;
                const value = syms[i];
                _ = syms[i].expectEither(&.{ .exp_true, .exp_false }) orelse continue;
                i += 1;
                _ = syms[i].expect(.op_rparan) orelse continue;
                ml.info("Found [compiler expression2] with identifier => {s} : value = {s}", .{ ident.token.data, value.token.data });
                continue;
            }

            ml.info("Found [compiler expression] with identifier => {s}", .{syms[i].token.data});
        }

        // Find the entry point "let"
        i = 0;
        while (i < syms.len) : (i += 1) {
            _ = syms[i].expect(.st_let) orelse continue;
            i += 1;
            var let_ident = syms[i];
            var r = syms[i].expectEither(&.{ .ident, .st_mut }) orelse continue;
            if (r == .st_mut) {
                i += 1;
                _ = syms[i].expect(.ident) orelse continue;

                let_ident = syms[i];
            }

            i += 1;
            _ = syms[i].expect(.st_type) orelse continue;
            i += 1;
            _ = syms[i].expect(.st_eq) orelse continue;
            i += 1;

            _ = syms[i].expect(.exp_compiler) orelse continue;
            i += 1;
            _ = syms[i].expect(.op_lparan) orelse continue;
            i += 1;
            _ = syms[i].expect(.ident) orelse continue;
            if (!mem.eql(u8, syms[i].token.data, "entry_point")) continue;
            i += 1;
            _ = syms[i].expect(.st_eq) orelse continue;
            i += 1;
            r = syms[i].expectEither(&.{ .exp_true, .exp_false }) orelse continue;
            if (r == .exp_false) continue;
            i += 1;
            _ = syms[i].expect(.op_rparan) orelse continue;
            i += 1;
            var cbracket: u32 = 1;
            var expr = std.ArrayList(u8).init(allocator);
            _ = syms[i].expect(.op_lcbracket) orelse continue;
            try expr.append(syms[i].token.data[0]);
            try expr.append('\n');
            i += 1;
            // whatever here is THE expression:
            while (cbracket > 0) : (i += 1) {
                var rr = syms[i].expect(.op_lcbracket);
                if (rr != null) cbracket += 1;

                rr = syms[i].expect(.op_rcbracket);
                if (rr != null) {
                    cbracket -= 1;
                    if (cbracket == 0) try expr.append('\n');
                }

                for (syms[i].token.data) |c| try expr.append(c);
                try expr.append(' ');

                rr = syms[i].expect(.st_semicolon);
                if (rr != null) try expr.append('\n');
            }
            _ = syms[i].expect(.st_semicolon) orelse continue;
            try expr.append(syms[i].token.data[0]);
            ml.info("Found \"entry point let\" => {s} : {s}", .{ let_ident.token.data, expr.items });
        }

        break :arena_alloc_blk;
    }
}
