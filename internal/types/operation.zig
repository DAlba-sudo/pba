// Operations are performed on accounts, and they make the account
// lose money, or gain money.
pub const Operation = struct {
    pub const Errors = error{
        OperationRetrievalFailure,
        OperationSearchFailure,
        OperationCreationFailure,
        OperationDeletionFailure,
        OperationUpdateFailure,
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
        \\  account_id INT REFERENCES account(id) ON DELETE CASCADE,
        \\  draft BOOLEAN NOT NULL DEFAULT FALSE
        \\ );
    ;

    // Upgrades databases created before `draft` existed; run after `DEF`.
    pub const MIGRATE_DRAFT: []const u8 =
        \\ ALTER TABLE operation ADD COLUMN IF NOT EXISTS draft BOOLEAN NOT NULL DEFAULT FALSE;
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
    // Drafts are listed but excluded from money totals.
    draft: bool,

    // Get
    pub fn get_by_id(p: *pg.Pool, allocator: std.mem.Allocator, id: i32) Errors!?Operation {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft FROM
            \\ operation WHERE id = $1 AND deleted_at IS NULL;
        ;

        var row = p.rowOpts(query, .{id}, .{ .column_names = true }) catch |err| {
            std.log.err("failed to get operation with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.OperationRetrievalFailure;
        };
        if (row) |r| {
            defer row.?.deinit() catch {};
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
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft FROM
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
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft FROM
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
    pub fn create(p: *pg.Pool, allocator: std.mem.Allocator, value: f64, date: i32, title: []const u8, comment: ?[]const u8, account_id: i32, draft: bool) Errors!Operation {
        const query =
            \\ INSERT INTO operation (value, date, title, comment, account_id, draft) VALUES ($1, $2, $3, $4, $5, $6)
            \\ RETURNING id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft;
        ;

        var row = p.row(query, .{ value, date, title, comment, account_id, draft }) catch |err| {
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

    // Inserts one independent operation per day in `dates` in one statement
    // and transaction, so either all rows are created or none. Returns them in
    // ascending date order, or null (nothing inserted) when the account is
    // unknown or deleted. `dates` must not be empty.
    pub fn create_many(p: *pg.Pool, allocator: std.mem.Allocator, value: f64, dates: []const i32, title: []const u8, comment: ?[]const u8, account_id: i32, draft: bool) Errors!?[]Operation {
        std.debug.assert(dates.len > 0);
        const query =
            \\ INSERT INTO operation (value, date, title, comment, account_id, draft)
            \\  SELECT $1, d, $3, $4, $5, $6 FROM unnest($2 ::int[]) AS d
            \\  WHERE EXISTS (SELECT 1 FROM account WHERE id = $5 AND deleted_at IS NULL)
            \\ RETURNING id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft;
        ;

        // A transaction so a failure while reading the rows back also undoes the insert.
        const c = p.acquire() catch |err| {
            std.log.err("failed to acquire a connection (err: {s})", .{@errorName(err)});
            return Errors.OperationCreationFailure;
        };
        defer c.release();
        c.begin() catch return Errors.OperationCreationFailure;
        errdefer c.rollback() catch {};

        var list: std.ArrayList(Operation) = .empty;
        {
            const rows = c.queryOpts(query, .{ value, dates, title, comment, account_id, draft }, .{ .column_names = true }) catch |err| {
                std.log.err("failed to create {d} recurring operations with title '{s}' (err: {s})", .{ dates.len, title, @errorName(err) });
                return Errors.OperationCreationFailure;
            };
            defer rows.deinit();

            var mapper = rows.mapper(Operation, .{ .dupe = true, .allocator = allocator });
            while (mapper.next() catch |err| {
                std.log.err("failed to map the row result to an operation (err: {s})", .{@errorName(err)});
                return Errors.OperationCreationFailure;
            }) |op| {
                list.append(allocator, op) catch return Errors.OperationCreationFailure;
            }
        }
        c.commit() catch |err| {
            std.log.err("failed to commit recurring operations (err: {s})", .{@errorName(err)});
            return Errors.OperationCreationFailure;
        };
        if (list.items.len == 0) return null;

        // RETURNING order is unspecified.
        std.mem.sort(Operation, list.items, {}, struct {
            fn lt(_: void, a: Operation, b: Operation) bool {
                return a.date < b.date or (a.date == b.date and a.id < b.id);
            }
        }.lt);
        return list.items;
    }

    // Update

    // Sets `draft` on a live operation. Returns the updated row, or null if
    // the id is unknown or deleted.
    pub fn set_draft(p: *pg.Pool, allocator: std.mem.Allocator, id: i32, draft: bool) Errors!?Operation {
        const query =
            \\ UPDATE operation SET draft = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1 AND deleted_at IS NULL
            \\ RETURNING id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft;
        ;

        var row = p.row(query, .{ id, draft }) catch |err| {
            std.log.err("failed to set draft on operation with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.OperationUpdateFailure;
        };
        if (row) |r| {
            defer row.?.deinit() catch {};
            return r.to(Operation, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an operation (err: {s})", .{@errorName(err)});
                return Errors.OperationUpdateFailure;
            };
        }

        return null;
    }

    // Sets `draft` on the live operations in `ids` that belong to `account_id`
    // (other ids are ignored). Returns how many were updated.
    pub fn set_draft_many(p: *pg.Pool, account_id: i32, ids: []const i32, draft: bool) Errors!usize {
        const query =
            \\ UPDATE operation SET draft = $3, updated_at = CURRENT_TIMESTAMP
            \\ WHERE account_id = $1 AND id = ANY($2) AND deleted_at IS NULL;
        ;

        const affected = p.exec(query, .{ account_id, ids, draft }) catch |err| {
            std.log.err("failed to set draft on {d} operations of account {d} (err: {s})", .{ ids.len, account_id, @errorName(err) });
            return Errors.OperationUpdateFailure;
        };
        return @intCast(affected orelse 0);
    }

    // Moves the live operations in `ids` that belong to `from_id` to `to_id`
    // (other ids are ignored). Nothing moves unless both accounts are live.
    // Returns how many were moved.
    pub fn move_many(p: *pg.Pool, from_id: i32, to_id: i32, ids: []const i32) Errors!usize {
        const query =
            \\ UPDATE operation SET account_id = $2, updated_at = CURRENT_TIMESTAMP
            \\ WHERE account_id = $1 AND id = ANY($3) AND deleted_at IS NULL
            \\  AND (SELECT count(*) FROM account WHERE id IN ($1, $2) AND deleted_at IS NULL) = 2;
        ;

        const affected = p.exec(query, .{ from_id, to_id, ids }) catch |err| {
            std.log.err("failed to move {d} operations from account {d} to {d} (err: {s})", .{ ids.len, from_id, to_id, @errorName(err) });
            return Errors.OperationUpdateFailure;
        };
        return @intCast(affected orelse 0);
    }

    // Parses a `draft` form value: "true" or "false", else null.
    pub fn parseDraft(s: []const u8) ?bool {
        if (std.mem.eql(u8, s, "true")) return true;
        if (std.mem.eql(u8, s, "false")) return false;
        return null;
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

    // Soft-deletes the live operations in `ids` that belong to `account_id`
    // (other ids are ignored). Returns how many were deleted.
    pub fn delete_live_many(p: *pg.Pool, account_id: i32, ids: []const i32) Errors!usize {
        const query =
            \\ UPDATE operation SET deleted_at = CURRENT_TIMESTAMP
            \\ WHERE account_id = $1 AND id = ANY($2) AND deleted_at IS NULL;
        ;

        const affected = p.exec(query, .{ account_id, ids }) catch |err| {
            std.log.err("failed to delete {d} operations of account {d} (err: {s})", .{ ids.len, account_id, @errorName(err) });
            return Errors.OperationDeletionFailure;
        };
        return @intCast(affected orelse 0);
    }

    pub fn get_by_account(p: *pg.Pool, allocator: std.mem.Allocator, account_id: i32) Errors![]Operation {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id, draft FROM
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

test "parseDraft" {
    try std.testing.expectEqual(@as(?bool, true), Operation.parseDraft("true"));
    try std.testing.expectEqual(@as(?bool, false), Operation.parseDraft("false"));
    for ([_][]const u8{ "", "on", "1", "TRUE" }) |s| try std.testing.expectEqual(null, Operation.parseDraft(s));
}

const std = @import("std");
const pg = @import("pg");
