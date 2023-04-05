# "Performance aware programming" course

My solutions and sandbox for course: https://www.computerenhance.com/

Solutions mostly written in zig or C/C++ (using zig build system).
`zig version 0.11.0-dev.1593+d24ebf1d1` is being used, different versions might or might not work.

## Haversine distance

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

### Notes

* Generator (40x speedup) from buffering file io. C/C++ standard library does it by default (if not disabled) however zig gives you full control over it therefore requires few extra lines of code.

### Results

All tests/benchmarking done using ~5 years old machine:

```
CPU: (Skylake) Intel i7-6700 CPU @ 3.40GHz
        turbo boost up to 4Ghz
        4 cores / 8 threads
        Cache L1: 	64K (per core)
        Cache L2: 	256K (per core)
        Cache L3: 	8MB (shared)
RAM: 32GB dual-channel (Crucial CT16G4DFRA266  2 x 16 GB DDR4 2666 MHz)
```

#### Generate

Generates 10M random coordinate pairs and prints them out in json format.
**8.84s**  

#### Basic implementation

* read whole file in memory
* parse (using default std.json.parser) into a struct
* loop over and do the math
Only optimization more or less is just to inline haversine function. Let the compiler optimize.

**1.4 million haversines/second**

```
BEST SUB-RESULTS:
(test-iterations: 20, input size: 10000000, float: f64)
        avg harvestine:          10008.47710
        read time:               828.909ms
        parse time:              5.415s
        math time:               654.993ms
        total time:              7.046s
        throughput:              1419120 haversines/second
```

#### streaming implementations

* stream parse and process at same time
