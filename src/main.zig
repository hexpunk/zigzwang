const std = @import("std");
const Io = std.Io;

const sqlite = @import("sqlite.zig");

pub fn main() !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // In order to do I/O operations need an `Io` instance.
    // const io = init.io;

    var db = try sqlite.SqliteDatabase.init("test.db");
    defer db.close();
}

test {
    std.testing.refAllDecls(@This());
}
