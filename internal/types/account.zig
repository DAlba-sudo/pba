// An account is tied to a user. It is used to manage multiple
// spending avenues (i.e., savings vs. debit, vs. credit, etc).
pub const Account = struct {
    pub const Errors = error{
        AccountRetrievalFailure,
        AccountSearchFailure,
        AccountCreationFailure,
        AccountDeletionFailure,
    };

    pub const DEF: []const u8 =
        \\ CREATE TABLE IF NOT EXISTS account (
        \\  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  deleted_at TIMESTAMP DEFAULT NULL,
        \\  initial_balance FLOAT,
        \\  name TEXT NOT NULL
        \\ );
    ;

    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    initial_balance: ?f64,
    name: []const u8,

    // Get
    pub fn get_by_id(p: *pg.Pool, allocator: std.mem.Allocator, id: i32) Errors!?Account {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, initial_balance, name FROM
            \\ account WHERE id = $1 AND deleted_at IS NULL;
        ;

        var row = p.rowOpts(query, .{id}, .{ .column_names = true }) catch |err| {
            std.log.err("failed to get account with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.AccountRetrievalFailure;
        };
        if (row) |r| {
            defer row.?.deinit() catch {};
            return r.to(Account, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an account (err: {s})", .{@errorName(err)});
                return Errors.AccountRetrievalFailure;
            };
        }

        return null;
    }

    // Search
    pub fn search_by_name(p: *pg.Pool, allocator: std.mem.Allocator, name: []const u8, limit: u32, page: i32) Errors![]Account {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, initial_balance, name FROM
            \\ account WHERE name ILIKE '%' || $1 ::text || '%' AND deleted_at IS NULL ORDER BY id ASC LIMIT $2 OFFSET $3
        ;

        const rows = p.queryOpts(query, .{ name, limit, page }, .{
            .column_names = true,
        }) catch |err| {
            std.log.err("failed to search the accounts by name (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        };
        defer rows.deinit();

        var list: std.ArrayList(Account) = .empty;
        const mapper = rows.mapper(Account, .{ .allocator = allocator });

        while (mapper.next() catch |err| {
            std.log.err("failed to map the row search result to an account (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        }) |acc| {
            list.append(allocator, acc) catch |err| {
                std.log.err("failed to append row search result to list (err: {s})", .{@errorName(err)});
                return Errors.AccountSearchFailure;
            };
        }

        return list.toOwnedSlice(allocator) catch |err| {
            std.log.err("failed to convert list to owned slice (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        };
    }

    // Filter for `search`. Default values disable each condition.
    pub const SearchFilter = struct {
        name: []const u8 = "", // ILIKE substring
        initial_balance: f32 = 0.0, // 0 = no filter (same as /api)
        after_id: ?i32 = null, // keyset cursor: only ids strictly greater
        limit: ?i32 = null, // null = no limit
    };

    // Returns live accounts matching `f`, ordered by id ascending. Rows are
    // copied into `allocator`.
    pub fn search(p: *pg.Pool, allocator: std.mem.Allocator, f: SearchFilter) Errors![]Account {
        const query =
            \\ SELECT id, created_at, updated_at, deleted_at, initial_balance, name FROM
            \\  account WHERE ($1 ::text = '' OR name ILIKE '%' || $1 ::text || '%')
            \\  AND ($2 ::float8 = 0.00 OR initial_balance = $2)
            \\  AND ($3 ::int IS NULL OR id > $3)
            \\  AND deleted_at IS NULL
            \\  ORDER BY id ASC LIMIT $4 ::int
        ;

        const rows = p.queryOpts(query, .{ f.name, f.initial_balance, f.after_id, f.limit }, .{
            .column_names = true,
        }) catch |err| {
            std.log.err("failed to search the accounts (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        };
        defer rows.deinit();

        var list: std.ArrayList(Account) = .empty;
        var mapper = rows.mapper(Account, .{ .dupe = true, .allocator = allocator });
        while (mapper.next() catch |err| {
            std.log.err("failed to map the row search result to an account (err: {s})", .{@errorName(err)});
            return Errors.AccountSearchFailure;
        }) |acc| {
            list.append(allocator, acc) catch return Errors.AccountSearchFailure;
        }
        return list.toOwnedSlice(allocator) catch Errors.AccountSearchFailure;
    }

    // Create
    pub fn create(p: *pg.Pool, allocator: std.mem.Allocator, name: []const u8, initial_balance: f64) Errors!Account {
        const query =
            \\ INSERT INTO account (name, initial_balance) VALUES ($1, $2)
            \\ RETURNING id, created_at, updated_at, deleted_at, initial_balance, name;
        ;

        var row = p.row(query, .{ name, initial_balance }) catch |err| {
            std.log.err("failed to create account with name '{s}', and initial balance of ${d} (err: {s})", .{ name, initial_balance, @errorName(err) });
            return Errors.AccountCreationFailure;
        };
        if (row) |r| {
            defer row.?.deinit() catch {};
            return r.to(Account, .{
                .dupe = true,
                .allocator = allocator,
            }) catch |err| {
                std.log.err("failed to map the row result to an account (err: {s})", .{@errorName(err)});
                return Errors.AccountCreationFailure;
            };
        }

        return Errors.AccountCreationFailure;
    }

    // Delete
    pub fn delete_by_id(p: *pg.Pool, id: i32) Errors!void {
        const query =
            \\ UPDATE account SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1;
        ;

        _ = p.exec(query, .{id}) catch |err| {
            std.log.err("failed to delete account with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.AccountDeletionFailure;
        };
    }

    // Soft-deletes a live account. Returns false if the id is unknown or
    // already deleted. Its operations are left untouched.
    pub fn delete_live(p: *pg.Pool, id: i32) Errors!bool {
        const query =
            \\ UPDATE account SET deleted_at = CURRENT_TIMESTAMP WHERE id = $1 AND deleted_at IS NULL;
        ;

        const affected = p.exec(query, .{id}) catch |err| {
            std.log.err("failed to delete account with id {d} (err: {s})", .{ id, @errorName(err) });
            return Errors.AccountDeletionFailure;
        };
        return (affected orelse 0) > 0;
    }
};

const std = @import("std");
const pg = @import("pg");
