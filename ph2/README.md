# PDC Project — Phase 2

**Hadoop MapReduce** on the UCI Household Power Consumption dataset (~2M rows).
Computes `avg / min / max` of `Global_active_power` via a single MR job. Mapper
buckets values across 16 keys; combiner pre-aggregates per mapper; reducer
emits per-bucket partial stats; the driver merges the K partials client-side
and writes the final aggregate back into HDFS.

The full write-up — diagrams, charts, screenshots — lives in **[`report.html`](report.html)**.
This README is the short, scannable version.

---

## Headline results

15 timed iterations per configuration (one warmup discarded). All times in milliseconds.
Speedup is computed against Hadoop @ 1 reducer (sequential and MPI live on a
different time scale; see "cross-stack reference" below).

| Implementation | reducers | best (ms) | median | mean | speedup |
|---|---:|---:|---:|---:|---:|
| hadoop          | 1 | 19,336 | 20,152 | 19,870 | 1.00× |
| hadoop          | 2 | 20,299 | 21,323 | 20,937 | 0.95× |
| hadoop          | 4 | 22,013 | 23,315 | 22,932 | 0.88× |
| hadoop          | 8 | 25,347 | 27,330 | 26,860 | 0.76× |
| **hadoop-uber** | 1 | **11,312** | 13,298 | 12,730 | **1.71×** |
| **hadoop-local** | 1 | **3,558** | 3,571 | 3,570 | **5.43×** |

More reducers → slower: container-launch overhead grows while per-reducer compute stays trivial (16 MB of doubles, combiner-shrunk shuffle).
See [§ Findings](#findings) for the breakdown and the speed-ladder showing how much overhead each mode removes.

Raw numbers (with cross-stack reference rows for Phase 1's sequential and
best-MPI configurations) are in [`results.csv`](results.csv).

---

## Dataset

| | |
|---|---|
| Source | UCI Household Power Consumption (archive.ics.uci.edu / 00235) |
| Column extracted | `Global_active_power` |
| Raw rows | 2,075,259 |
| After NaN drop | **2,049,280** |
| Phase 2 input format | text, one float per line (`../data/data.txt`, ~12 MB) |
| HDFS path | `hdfs:///input/data.txt` |

NumPy reference (every MR run is checked against this):

```
sum  = 2237024.862000
mean =       1.091615
min  =       0.076000
max  =      11.122000
```

Reference values live in `../data/data.meta.txt`.

---

## Architecture

A single MR job collapses the three aggregates into one pass:

```
hdfs:///input/data.txt
        │
        ▼
   StatsMapper   ──►  (bucket = lineNo % 16, PowerStats{sum=v, count=1, min=v, max=v})
        │
        ▼
  StatsReducer    used as combiner — partial merge per mapper, cuts shuffle bytes
        │  shuffle
        ▼
  StatsReducer    final per-bucket merge — emits K part-r-* SequenceFiles
        │
        ▼
     Driver       reads K parts, merges client-side, writes final to
                  hdfs:///output/final/stats.txt
```

### Why bucket by `lineNo % 16`?

If every value emitted the same key, all data would shuffle to a single reducer
regardless of how many we configured — the sweep would be meaningless. With
16 fixed buckets, Hadoop's default `HashPartitioner` spreads the load evenly
across 1, 2, 4, or 8 reducers and the sweep actually measures parallel reduce
work.

### MapReduce primitives used

| Step | Primitive | Purpose |
|---|---|---|
| 1 | `Mapper.map` | Parse line → emit `(bucket, singleton stats)` |
| 2 | `Reducer` as combiner | Mapper-local partial merge before shuffle |
| 3 | `HashPartitioner` (default) | Distribute 16 keys across K reducers |
| 4 | `Reducer.reduce` | Per-bucket merge → K `part-r-*` files |
| 5 | `SequenceFile.Reader` (driver) | Read K partials, final client-side merge |
| 6 | `FileSystem.create` | Write the final one-line summary back to HDFS |

---

## Repository layout

```
ph2/
├── docker/
│   ├── run-cluster.sh           # spin up apache/hadoop pseudo-distributed
│   ├── init-hadoop.sh           # runs inside container: configs + format + daemons
│   └── extract-hadoop-jars.sh   # one-time copy of /opt/hadoop/share/... to host
├── src/main/java/com/pdc/
│   ├── PowerStats.java          # custom Writable {sum, count, min, max}
│   ├── StatsMapper.java         # bucket + singleton-stats emit
│   ├── StatsReducer.java        # combiner + reducer (same class)
│   └── Driver.java              # job submission, client-side final merge, HDFS write
├── bench/
│   ├── benchmark.sh             # 15 runs × 4 reducer counts
│   └── benchmark.ps1            # PowerShell mirror
├── bin/                         # built JAR (gitignored)
├── outputs/                     # stdout captures + SVG terminal screenshots
│   └── index.html               # gallery
├── .hadoop-jars/                # extracted Hadoop jars for host compile (gitignored)
├── Makefile                     # all / put / test / bench / clean
├── results.csv                  # benchmark table + phase 1 reference rows
├── report.html                  # full report
└── README.md
```

---

## Setup (one time)

Only Docker and a JDK are needed on the host — Hadoop itself runs inside the
container.

### Linux / macOS

1. **Docker** — Fedora `sudo dnf install docker && sudo systemctl enable --now docker`,
   Debian/Ubuntu `sudo apt install docker.io`, macOS `brew install --cask docker`.
2. **JDK** with `javac` (any version with `--release 8` support — Java 9+).
   Fedora: `sudo dnf install java-latest-openjdk-devel`.
3. **Python 3 + numpy/pandas** if you need to re-run `data/prep.py`.

### Windows

1. Docker Desktop with WSL 2 backend.
2. JDK from Adoptium (`winget install EclipseAdoptium.Temurin.21.JDK`).
3. Python with pandas/numpy in PATH.

---

## Running it

Run everything from this `ph2/` directory. The dataset is shared with `ph1/`
at `../data/data.txt`; if it doesn't exist yet, run `python3 ../data/prep.py`
first.

### Linux / macOS

```bash
./docker/run-cluster.sh                          # start container, init HDFS+YARN
./docker/extract-hadoop-jars.sh                  # one-time: hadoop jars → .hadoop-jars/
make                                             # builds bin/phase2-mr.jar (host javac)
make put                                         # uploads data.txt into HDFS once
make test                                        # single end-to-end run at 4 reducers
make bench                                       # full sweep, writes results.csv
```

### Windows (PowerShell)

```powershell
.\docker\run-cluster.sh                          # via WSL or git-bash
.\docker\extract-hadoop-jars.sh
make                                             # (or run javac/jar manually if no make)
.\bench\benchmark.ps1                            # full sweep
```

---

## Correctness

Every reducer count must produce `avg = 1.091615`, `min = 0.076`,
`max = 11.122` — matching `data/data.meta.txt` to within `1e-9` (`min` / `max`
are bit-exact). The Driver prints this as the last `[mr] n= ... avg= ... min= ... max= ...`
line; the benchmark sweep aborts (well, fails the awk parse) if `elapsed_ms`
is missing.

The final result is also written to `hdfs:///output/final/stats.txt`:
```bash
docker exec -u hadoop hadoop-pseudo hdfs dfs -cat /output/final/stats.txt
# n=2049280 avg=1.091615037 min=0.076000000 max=11.122000000 reduces=4 elapsed_ms=XXXXX
```
which satisfies the "Generate the final result in HDFS" requirement.

---

## Findings

**1 · Fixed startup overhead dominates.** Each MR job takes seconds to launch
the application master, request containers, and tear down — that fixed cost is
orders of magnitude larger than the actual aggregation of 16 MB of doubles.
This is the Phase 2 analog of Phase 1's "memory-bandwidth-bound" finding: in
both cases the framework cost overwhelms the per-element work.

**2 · Reducer count barely matters on one node.** With combiner-side
pre-aggregation, the shuffle is already tiny (K mappers × 16 buckets × ~40
bytes/PowerStats = a few KB). Adding reducers buys us almost no parallelism on
a single node — the work being parallelised is dwarfed by per-reducer container
startup.

**3 · Cross-stack scale comparison.** The phase 1 MPI implementation finishes
the same aggregate in ~1 ms (best, n=2). Hadoop's per-job overhead is roughly
**31,000× larger**. The point of Hadoop isn't single-machine speed; it's the
ability to run unchanged across thousands of nodes on petabyte data. On a
2-million-row dataset on one machine, sequential C wins. This is the honest
"when to reach for which tool" story.

### Where the 19 seconds go

Approximate per-job breakdown of a single `--reduces 1` run:

| Stage | Time | What |
|---|---|---|
| `hadoop jar` JVM startup + RM connect | ~2 s | Cold-load Hadoop client |
| AM container scheduling + JVM | ~4 s | RM picks node, NM launches AppMaster |
| Map container negotiation + JVMs | ~6 s | Heartbeat-driven, one JVM per split |
| Shuffle + sort | ~1 s | Disk write/read even though combiner cut payload to KB |
| Reduce container + JVM | ~4 s | Same negotiation pattern as maps |
| AM cleanup + output commit | ~2 s | Final HDFS commit, AM teardown |
| **Actual compute on 16 MB** | **~0.1 s** | What the job nominally does |

>99% of the wallclock is framework. The actual aggregation is trivial.

### Speed ladder — three modes empirically measured

| Mode | Best (ms) | vs default | What it skips |
|---|---:|---:|---|
| Default MR + YARN | 19,336 | 1.00× | Nothing — full cluster path |
| Uber mode (`-Dmapreduce.job.ubertask.enable=true`) | 11,312 | **1.71×** | Map/reduce containers — AM runs the whole job in-process |
| LocalJobRunner (`-Dmapreduce.framework.name=local`) | 3,558 | **5.43×** | YARN entirely — whole MR runs in the client JVM. Still reads from HDFS. |
| Phase 1 sequential C (for scale) | 3.18 | 6,080× | Hadoop entirely. Native compiled code, no JVM. |
| Phase 1 MPI @ 2 (for scale) | 0.609 | 31,750× | As above + shared-memory parallelism. |

LocalJobRunner runs the **same Mapper/Reducer/Driver code** as the YARN path —
the 5.4× speedup is pure overhead removal, no algorithmic change. The
remaining ~3.5 s is JVM cold-start (~1 s) + Hadoop framework class loading
(~1.5 s) + actual in-process MR step (~1 s). The "slowness" of Hadoop on tiny
data is the cluster machinery, not MapReduce.

**Practical takeaways**: unit-test your MR jobs against LocalJobRunner — same
correctness signal in ~3 s instead of ~20 s per iteration. Don't reach for
full YARN until the per-job compute is large enough that ~15 s of overhead is
a small percentage of total — rule of thumb, minutes-scale jobs on
hundreds-of-GB inputs.

### Measurement hygiene

- **Warmup pass** discards the first run so JVM JIT / HDFS cache are warm.
- **Wallclock from `submit` to `job completion + final HDFS write`** — the same
  scope Phase 1 measured (data fetch + compute + reduce, no I/O setup).
- **`MPI_Barrier`-equivalent** — `Job.waitForCompletion(true)` is blocking, so
  there's no early-finish race.
- **Best of 15 runs** is the headline; container scheduling noise is the
  dominant variance source.

---

## Outputs / screenshots

`outputs/` contains stdout captures (`*.txt`) from a representative single
job, the four reducer-count benchmark rows, the full sweep, and a re-print of
the NumPy reference. SVG terminal-style screenshots used by the report and a
small gallery at [`outputs/index.html`](outputs/index.html).

The full report — pipeline diagram, architecture flow, requirements checklist,
results charts, screenshots and findings — is in **[`report.html`](report.html)**.
