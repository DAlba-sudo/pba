# Vendored zmpl

- Upstream: https://github.com/jetzig-framework/zmpl @ 0cb5ef895b3a8b84792c2284418160bb0d0930ff
- Original package hash: `zmpl-0.0.1-SYFGBrWyAwALhLkr0lYAlb192HFj9wf0lFpc7iLkqkEP`
- Patch: `src/manifest/main.zig` adds `try writer.interface.flush();` before `file.close(io)`; without it the generated `zmpl.manifest.zig` is truncated.
- Drop this vendored copy and return to the url/hash dependency once upstream flushes the writer.
