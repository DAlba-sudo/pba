// Operations are performed on accounts, and they make the account
// lose money, or gain money.
pub const Operation = struct {
    pub const Errors = error{
        OperationRetrievalFailure,
        OperationSearchFailure,
        OperationCreationFailure,
        OperationDeletionFailure,
    };

    pub const DEF: []const u8 =
        \\ CREATE TABLE IF NOT EXISTS operation (
        \\  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  deleted_at TIMESTAMP DEFAULT NULL,
        \\  value FLOAT NOT NULL,
        \\  date INT NOT NULL,
        \\  title TEXT NOT NULL,
        \\  comment TEXT,
        \\  account_id INT REFERENCES account(id) ON DELETE CASCADE
        \\ );
    ;

    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    value: f64,
    date: i32,
    title: []const u8,
    comment: ?[]const u8,
    account_id: i32,

    // Get
    pub fn get_by_id(p: *pg.Pool, allocator: std.mem.Allocator, id: i32) Errors!?Operation {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id FROM
            \\ operation WHERE id = $1 AND deleted_at IS NULL;
        ;

        const row = p.rowOpts(query, .{id}, .{ .column_names = true }) catch |err| {
            std.log.err("failed to get operation with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.OperationRetrievalFailure;
        };
        if (row) |r| {
            defer r.deinit();
            return r.to(Operation, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an operation (err: {s})", .{@errorName(err)});
                return Errors.OperationRetrievalFailure;
            };
        }

        return null;
    }

    // Search
    pub fn search_by_title(p: *pg.Pool, allocator: std.mem.Allocator, title: []const u8, limit: i32, page: i32) Errors![]Operation {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id FROM
            \\ operation WHERE title ILIKE '%' || $1 ::text || '%' AND deleted_at IS NULL ORDER BY id ASC LIMIT $2 OFFSET $3
        ;

        const rows = p.queryOpts(query, .{ title, limit, page }, .{
            .column_names = true,
        }) catch |err| {
            std.log.err("failed to search the operations by title (err: {s})", .{@errorName(err)});
            return Errors.OperationSearchFailure;
        };
        defer rows.deinit();

        var list: std.ArrayList(Operation) = .empty;
        const mapper = rows.mapper(Operation, .{ .allocator = allocator });

        while (mapper.next() catch |err| {
            std.log.err("failed to map the row search result to an operation (err: {s})", .{@errorName(err)});
            return Errors.OperationSearchFailure;
        }) |op| {
            list.append(allocator, op) catch |err| {
                std.log.err("failed to append row search result to list (err: {s})", .{@errorName(err)});
                return Errors.OperationSearchFailure;
            };
        }

        return list.toOwnedSlice(allocator) catch |err| {
            std.log.err("failed to convert list to owned slice (err: {s})", .{@errorName(err)});
            return Errors.OperationSearchFailure;
        };
    }

    // Keyset position of a row in (date DESC, id DESC) order.
    pub const Cursor = struct { date: i32, id: i32 };

    // Filter for `search`. Default values disable each condition.
    pub const SearchFilter = struct {
        title: []const u8 = "", // ILIKE substring
        comment: []const u8 = "", // ILIKE substring
        account_id: ?i32 = null,
        date: ?i32 = null, // exact day
        date_max: ?i32 = null, // inclusive upper bound
        text: []const u8 = "", // ILIKE substring of title OR comment
        limit: ?i32 = null, // null = no limit
        cursor: ?Cursor = null, // only rows strictly after it
    };

    // Returns live operations matching `f`, ordered by date then id, both
    // descending. Rows are copied into `allocator`. ILIKE wildcards (`%`, `_`)
    // in the text filters are not escaped.
    pub fn search(p: *pg.Pool, allocator: std.mem.Allocator, f: SearchFilter) Errors![]Operation {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id FROM
            \\  operation WHERE deleted_at IS NULL
            \\  AND ($1 ::text = '' OR title ILIKE '%' || $1 ::text || '%')
            \\  AND ($2 ::text = '' OR comment ILIKE '%' || $2 ::text || '%')
            \\  AND ($3 ::int IS NULL OR date = $3)
            \\  AND ($4 ::int IS NULL OR account_id = $4)
            \\  AND ($5 ::int IS NULL OR date <= $5)
            \\  AND ($6 ::text = '' OR title ILIKE '%' || $6 ::text || '%' OR comment ILIKE '%' || $6 ::text || '%')
            \\  AND ($8 ::int IS NULL OR (date, id) < ($8 ::int, $9 ::int))
            \\  ORDER BY date DESC, id DESC LIMIT $7 ::int
        ;

        const cursor_date: ?i32 = if (f.cursor) |c| c.date else null;
        const cursor_id: ?i32 = if (f.cursor) |c| c.id else null;
        const rows = p.queryOpts(query, .{
            f.title,
            f.comment,
            f.date,
            f.account_id,
            f.date_max,
            f.text,
            f.limit,
            cursor_date,
            cursor_id,
        }, .{ .column_names = true }) catch |err| {
            std.log.err("failed to search the operations (err: {s})", .{@errorName(err)});
            return Errors.OperationSearchFailure;
        };
        defer rows.deinit();

        var list: std.ArrayList(Operation) = .empty;
        var mapper = rows.mapper(Operation, .{ .dupe = true, .allocator = allocator });
        while (mapper.next() catch |err| {
            std.log.err("failed to map the row search result to an operation (err: {s})", .{@errorName(err)});
            return Errors.OperationSearchFailure;
        }) |op| {
            list.append(allocator, op) catch return Errors.OperationSearchFailure;
        }
        return list.toOwnedSlice(allocator) catch Errors.OperationSearchFailure;
    }

    // Create
    pub fn create(p: *pg.Pool, allocator: std.mem.Allocator, value: f64, date: i32, title: []const u8, comment: ?[]const u8, account_id: i32) Errors!Operation {
        const query =
            \\ INSERT INTO operation (value, date, title, comment, account_id) VALUES ($1, $2, $3, $4, $5)
            \\ RETURNING id, created_at, updated_at, deleted_at, value, date, title, comment, account_id;
        ;

        var row = p.row(query, .{ value, date, title, comment, account_id }) catch |err| {
            std.log.err("failed to create operation with title '{s}', and value of ${d} (err: {s})", .{ title, value, @errorName(err) });
            return Errors.OperationCreationFailure;
        };
        if (row) |r| {
            defer row.?.deinit() catch {};
            return r.to(Operation, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an operation (err: {s})", .{@errorName(err)});
                return Errors.OperationCreationFailure;
            };
        }

        return Errors.OperationCreationFailure;
    }

    // Delete
    pub fn delete_by_id(p: *pg.Pool, id: i32) Errors!void {
        const query =
            \\ UPDATE operation SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1;
        ;

        _ = p.exec(query, .{id}) catch |err| {
            std.log.err("failed to delete operation with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.OperationDeletionFailure;
        };
    }

    // Soft-deletes a live operation. Returns false if the id is unknown or
    // already deleted.
    pub fn delete_live(p: *pg.Pool, id: i32) Errors!bool {
        const query =
            \\ UPDATE operation SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1 AND deleted_at IS NULL;
        ;

        const affected = p.exec(query, .{id}) catch |err| {
            std.log.err("failed to delete operation with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.OperationDeletionFailure;
        };
        return (affected orelse 0) > 0;
    }

    pub fn get_by_account(p: *pg.Pool, allocator: std.mem.Allocator, account_id: i32) Errors![]Operation {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id FROM
            \\ operation WHERE account_id = $1 AND deleted_at IS NULL ORDER BY id ASC;
        ;

        var rows = p.queryOpts(query, .{account_id}, .{
            .column_names = true,
        }) catch |err| {
            std.log.err("failed to get operations by account with id {d} (err: {s})", .{ account_id, @errorName(err) });
            return Errors.OperationRetrievalFailure;
        };
        defer rows.deinit();

        var list: std.ArrayList(Operation) = .empty;
        const mapper = rows.mapper(Operation, .{ .allocator = allocator });

        while (mapper.next() catch |err| {
            std.log.err("failed to map the row search result to an operation (err: {s})", .{@errorName(err)});
            return Errors.OperationRetrievalFailure;
        }) |op| {
            list.append(allocator, op) catch |err| {
                std.log.err("failed to append row search result to list (err: {s})", .{@errorName(err)});
                return Errors.OperationRetrievalFailure;
            };
        }

        return list.toOwnedSlice(allocator) catch |err| {
            std.log.err("failed to convert list to owned slice (err: {s})", .{@errorName(err)});
            return Errors.OperationRetrievalFailure;
        };
    }
};

const std = @import("std");
const pg = @import("pg");
