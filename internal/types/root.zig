// The user will not be added until Phase 2 of this program's release.
// Right now, it will simply act as a stub.
pub const User = struct {
    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
};

// An account is tied to a user. It is used to manage multiple
// spending avenues (i.e., savings vs. debit, vs. credit, etc).
pub const Account = struct {
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
    initial_balance: ?f32,
    name: []const u8,
};

// Operations are performed on accounts, and they make the account
// lose money, or gain money.
pub const Operation = struct {
    // NOTE: DOUBLE may not work, potentially switch to FLOAT or something else.
    pub const DEF: []const u8 =
        \\ CREATE TABLE IF NOT EXISTS operation (
        \\  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \\  deleted_at TIMESTAMP DEFAULT NULL,
        \\  value FLOAT NOT NULL,
        \\  date TIMESTAMP NOT NULL,
        \\  title TEXT NOT NULL,
        \\  comment TEXT,
        \\  account_id INT REFERENCES account(id) ON DELETE CASCADE
        \\ );
    ;

    id: i32,
    created_at: i64,
    updated_at: i64,
    deleted_at: ?i64,
    value: f32,
    date: i64,
    title: []const u8,
    comment: ?[]const u8,
    account_id: i32,
};

const std = @import("std");
