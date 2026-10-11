const crud = @import("crud.zig");
const search = @import("search.zig");

pub const Create = crud.create;
pub const Delete = crud.delete;
pub const GetId = crud.get_id;
pub const Search = search.search;
