const sqlite = @import("sqlite");

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
    if (rc != sqlite.SQLITE_OK) {
        switch (rc) {
            sqlite.SQLITE_INTERNAL => return SqliteError.Internal,
            sqlite.SQLITE_PERM => return SqliteError.PermissionDenied,
            sqlite.SQLITE_ABORT => return SqliteError.Abort,
            sqlite.SQLITE_BUSY => return SqliteError.Busy,
            sqlite.SQLITE_LOCKED => return SqliteError.Locked,
            sqlite.SQLITE_NOMEM => return SqliteError.MoMemory,
            sqlite.SQLITE_READONLY => return SqliteError.ReadOnly,
            sqlite.SQLITE_INTERRUPT => return SqliteError.Interrupt,
            sqlite.SQLITE_IOERR => return SqliteError.IoError,
            sqlite.SQLITE_CORRUPT => return SqliteError.Corrupt,
            sqlite.SQLITE_NOTFOUND => return SqliteError.NotFound,
            sqlite.SQLITE_FULL => return SqliteError.Full,
            sqlite.SQLITE_CANTOPEN => return SqliteError.CannotOpen,
            sqlite.SQLITE_PROTOCOL => return SqliteError.Protocol,
            sqlite.SQLITE_EMPTY => return SqliteError.Empty,
            sqlite.SQLITE_SCHEMA => return SqliteError.SchemaChanged,
            sqlite.SQLITE_TOOBIG => return SqliteError.BlobTooBig,
            sqlite.SQLITE_CONSTRAINT => return SqliteError.ConstraintViolation,
            sqlite.SQLITE_MISMATCH => return SqliteError.TypeMismatch,
            sqlite.SQLITE_MISUSE => return SqliteError.LibraryMisuse,
            sqlite.SQLITE_NOLFS => return SqliteError.NoLFS,
            sqlite.SQLITE_AUTH => return SqliteError.AuthorizationDenied,
            sqlite.SQLITE_FORMAT => return SqliteError.Format,
            sqlite.SQLITE_RANGE => return SqliteError.OutOfRange,
            sqlite.SQLITE_NOTADB => return SqliteError.NotADatabase,
            sqlite.SQLITE_NOTICE => return SqliteError.Notification,
            sqlite.SQLITE_WARNING => return SqliteError.Warning,
            sqlite.SQLITE_ROW => return SqliteError.RowReady,
            sqlite.SQLITE_DONE => return SqliteError.Done,
            else => return SqliteError.Generic,
        }
    }
}

pub const SqliteDatabase = struct {
    handle: ?*sqlite.sqlite3,

    pub fn init(path: []const u8) !SqliteDatabase {
        var h: ?*sqlite.sqlite3 = undefined;
        try checkError(sqlite.sqlite3_open(path.ptr, &h));
        const handle = h orelse @panic("sqlite3_open succeeded but handle is null");
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA journal_mode = WAL;", null, null, null));
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA synchronous = NORMAL;", null, null, null));
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA busy_timeout = 5000;", null, null, null));
        // Setting the cache size to a negative value means it's interpreted as kibibytes, so this sets it to 64 MiB.
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA cache_size = -64000;", null, null, null));
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA temp_store = MEMORY;", null, null, null));
        // Setting the mmap size to 256 MiB allows SQLite to use memory-mapped I/O for databases smaller than that size, which can improve performance.
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA mmap_size = 268435456;", null, null, null));
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA foreign_keys = ON;", null, null, null));
        try checkError(sqlite.sqlite3_exec(handle, "PRAGMA auto_vacuum = INCREMENTAL;", null, null, null));

        return SqliteDatabase{
            .handle = handle,
        };
    }

    pub fn close(self: *SqliteDatabase) void {
        if (self.handle) |h| {
            _ = sqlite.sqlite3_close(h);
            self.handle = null;
        } else {
            @panic("attempted to close a database that was not open");
        }
    }
};
