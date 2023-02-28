# "Performance aware programming" course

My solutions and sandbox for course: https://www.computerenhance.com/

Solutions mostly written in zig or C/C++ (using zig build system).
`zig version 0.11.0-dev.1593+d24ebf1d1` is being used, different versions might or might not work.

## Harvestine distance
[haversine.zig](src/haversine.zig)
### How to run
If you don't have data set, first generate it:
```bash
zig build -Doptimize=ReleaseFast run -- -f 10m.json -g 10000000
```

Run processing & benchmarking:
```bash
zig build -Doptimize=ReleaseFast run -- -f 10m.json -i 5 -r
```
