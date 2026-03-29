const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const SqliteError = error{
    Generic,
    Internal,
    PermissionDenied,
    Abort,
    Busy,
    Locked,
    MoMemory,
    ReadOnly,
    Interrupt,
    IoError,
    Corrupt,
    NotFound,
    Full,
    CannotOpen,
    Protocol,
    Empty,
    SchemaChanged,
    BlobTooBig,
    ConstraintViolation,
    TypeMismatch,
    LibraryMisuse,
    NoLFS,
    AuthorizationDenied,
    Format,
    OutOfRange,
    NotADatabase,
    Notification,
    Warning,
    RowReady,
    Done,
};

fn checkError(rc: c_int) !void {
    if (rc != c.SQLITE_OK) {
        switch (rc) {
            c.SQLITE_INTERNAL => return SqliteError.Internal,
            c.SQLITE_PERM => return SqliteError.PermissionDenied,
            c.SQLITE_ABORT => return SqliteError.Abort,
            c.SQLITE_BUSY => return SqliteError.Busy,
            c.SQLITE_LOCKED => return SqliteError.Locked,
            c.SQLITE_NOMEM => return SqliteError.MoMemory,
            c.SQLITE_READONLY => return SqliteError.ReadOnly,
            c.SQLITE_INTERRUPT => return SqliteError.Interrupt,
            c.SQLITE_IOERR => return SqliteError.IoError,
            c.SQLITE_CORRUPT => return SqliteError.Corrupt,
            c.SQLITE_NOTFOUND => return SqliteError.NotFound,
            c.SQLITE_FULL => return SqliteError.Full,
            c.SQLITE_CANTOPEN => return SqliteError.CannotOpen,
            c.SQLITE_PROTOCOL => return SqliteError.Protocol,
            c.SQLITE_EMPTY => return SqliteError.Empty,
            c.SQLITE_SCHEMA => return SqliteError.SchemaChanged,
            c.SQLITE_TOOBIG => return SqliteError.BlobTooBig,
            c.SQLITE_CONSTRAINT => return SqliteError.ConstraintViolation,
            c.SQLITE_MISMATCH => return SqliteError.TypeMismatch,
            c.SQLITE_MISUSE => return SqliteError.LibraryMisuse,
            c.SQLITE_NOLFS => return SqliteError.NoLFS,
            c.SQLITE_AUTH => return SqliteError.AuthorizationDenied,
            c.SQLITE_FORMAT => return SqliteError.Format,
            c.SQLITE_RANGE => return SqliteError.OutOfRange,
            c.SQLITE_NOTADB => return SqliteError.NotADatabase,
            c.SQLITE_NOTICE => return SqliteError.Notification,
            c.SQLITE_WARNING => return SqliteError.Warning,
            c.SQLITE_ROW => return SqliteError.RowReady,
            c.SQLITE_DONE => return SqliteError.Done,
            else => return SqliteError.Generic,
        }
    }
}

pub const SqliteDatabase = struct {
    handle: ?*c.sqlite3,

    pub fn init(path: []const u8) !SqliteDatabase {
        var h: ?*c.sqlite3 = undefined;
        try checkError(c.sqlite3_open(path.ptr, &h));
        const handle = h orelse return SqliteError.Generic;
        try checkError(c.sqlite3_exec(handle, "PRAGMA journal_mode = WAL;", null, null, null));
        try checkError(c.sqlite3_exec(handle, "PRAGMA synchronous = NORMAL;", null, null, null));
        try checkError(c.sqlite3_exec(handle, "PRAGMA busy_timeout = 5000;", null, null, null));
        // Setting the cache size to a negative value means it's interpreted as kibibytes, so this sets it to 64 MiB.
        try checkError(c.sqlite3_exec(handle, "PRAGMA cache_size = -64000;", null, null, null));
        try checkError(c.sqlite3_exec(handle, "PRAGMA temp_store = MEMORY;", null, null, null));
        // Setting the mmap size to 256 MiB allows SQLite to use memory-mapped I/O for databases smaller than that size, which can improve performance.
        try checkError(c.sqlite3_exec(handle, "PRAGMA mmap_size = 268435456;", null, null, null));
        try checkError(c.sqlite3_exec(handle, "PRAGMA foreign_keys = ON;", null, null, null));
        try checkError(c.sqlite3_exec(handle, "PRAGMA auto_vacuum = INCREMENTAL;", null, null, null));

        return SqliteDatabase{
            .handle = handle,
        };
    }

    pub fn close(self: *SqliteDatabase) void {
        if (self.handle) |h| {
            _ = c.sqlite3_close(h);
            self.handle = null;
        }
    }
};
