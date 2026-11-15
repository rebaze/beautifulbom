# Findings

Observations, not promised limits. Machine: Apple Silicon Mac, macOS 27.2.1, Xcode 27.2 (Swift 6.4.2).

## Engine (`make bench`, release build, 2026-11-15)

| File | Size | Nodes | SourceDocument | Parse | `node(at:)` | Lex 64 KiB | Peak RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| cern-lhc-vdm-editor (CDX 1.2) | 40 KB | 1 109 | 0.1 ms | 0.3 ms | 0.1 µs | 47 µs | 6 MB |
| laravel-7.12.0 (CDX 1.4) | 140 KB | 2 732 | 0.3 ms | 0.7 ms | 0.1 µs | 265 µs | 7 MB |
| synthetic, pretty | 1 MB | 29 279 | 2.0 ms | 5.8 ms | 0.1 µs | 168 µs | 11 MB |
| synthetic, minified | 1 MB | 46 569 | 2.0 ms | 8.8 ms | 0.2 µs | 158 µs | 11 MB |
| synthetic, pretty | 10 MB | 291 004 | 21 ms | 57 ms | 0.5 µs | 164 µs | 51 MB |
| synthetic, minified | 10 MB | 461 054 | 18 ms | 91 ms | 0.7 µs | 163 µs | 63 MB |
| synthetic, pretty | 50 MB | 1 449 510 | 103 ms | 307 ms | 1.1 µs | 143 µs | 241 MB |
| synthetic, minified | 50 MB | 2 293 053 | 91 ms | 445 ms | 2.7 µs | 158 µs | 301 MB |

- Peak memory is about 5–6× the file size: file bytes, the decoded `String`, the `Data` read buffer and the node arena (11 `Int32` columns plus the kind, about 45 bytes per node). Well inside the plan's 10× threshold, so the arena layout stays.
- Lexing a 64 KiB window costs the same in the middle of a 50 MB single-line file as in a 1 MB one: highlighting is bounded by the visible range, not by the line.
- Minified files have about 1.6× the nodes per byte, because there is no whitespace.
