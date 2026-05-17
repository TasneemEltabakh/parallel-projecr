# PDC Project — Phase 1

**Sequential vs MPI** on the UCI Household Power Consumption dataset (~2M rows).
Both programs compute `avg / min / max` of `Global_active_power` in a single pass; the
MPI version distributes the array with `MPI_Scatterv` and combines partial results with
`MPI_Reduce`.

The full write-up — diagrams, charts, screenshots — lives in **[`report.html`](report.html)**.
This README is the short, scannable version.

---

## Headline results

15 timed iterations per configuration (one warmup discarded). All times in milliseconds.

| Implementation | n_procs | best  | median | mean  | speedup |
|----------------|--------:|------:|-------:|------:|--------:|
| sequential     |       1 | 3.176 |  3.637 | 3.685 |   1.00× |
| mpi            |       1 | 1.006 |  1.200 | 1.220 |   3.16× |
| **mpi**        |   **2** | **0.609** | **1.279** | **1.257** | **5.22× ← fastest** |
| mpi            |       4 | 0.711 |  1.177 | 1.133 |   4.47× |
| mpi            |       8 | 0.886 |  1.477 | 1.446 |   3.58× |

Raw numbers are in [`results.csv`](results.csv).

---

## Dataset

| | |
|---|---|
| Source | UCI Household Power Consumption (archive.ics.uci.edu / 00235) |
| Column extracted | `Global_active_power` |
| Raw rows | 2,075,259 |
| After NaN drop | **2,049,280** |
| On-disk format | flat little-endian float64 |
| `data.bin` size | 16.4 MB |

NumPy reference (every C run is checked against this):

```
sum  = 2237024.862000
mean =       1.091615
min  =       0.076000
max  =      11.122000
```

Reference values live in `data/data.meta.txt`.

---

## Architecture

**Sequential** — `fread` the whole array into `a[N]`, run a warmup pass to make the timed
region measure steady-state DRAM, then a single timed pass computes sum / max / min.
Time is taken with `QueryPerformanceCounter` for sub-millisecond resolution.

**MPI** — rank 0 reads the file. `MPI_Bcast` shares `N`; `MPI_Scatterv` distributes the
array (handles `N % np != 0`); each rank does a local sum / max / min over its chunk;
three `MPI_Reduce` calls combine the partials at rank 0. The timed region is bounded by
`MPI_Barrier` + `MPI_Wtime` so no rank gets a head start.

### MPI primitives used

| Step | Primitive | Purpose |
|------|-----------|---------|
| 1 | `MPI_Bcast` | Send array length `N` from rank 0 to every rank |
| 2 | `MPI_Scatterv` | Distribute the array in per-rank chunks (uneven splits OK) |
| 3 | `MPI_Reduce × 3` | Combine partial SUM / MAX / MIN at rank 0 |
| 4 | `MPI_Wtime` | High-resolution clock around the compute region |

---

## Repository layout

```
Project/
├── data/                            # shared between ph1 and ph2
│   ├── prep.py                      # downloads UCI archive, writes data.bin
│   ├── data.bin                     # 16.4 MB float64 array (gitignored)
│   └── data.meta.txt                # NumPy reference values
├── ph1/                             # ← you are here
│   ├── src/
│   │   ├── sequential.c             # single-process baseline
│   │   ├── parallel_mpi.c           # MPI Scatterv + Reduce
│   │   └── build.ps1                # gcc + MS-MPI linkage (Windows)
│   ├── bench/
│   │   ├── benchmark.ps1            # Windows sweep
│   │   └── benchmark.sh             # Linux/macOS sweep
│   ├── bin/                         # built binaries (gitignored)
│   ├── outputs/                     # real stdout captures + SVG screenshots
│   ├── Makefile                     # gcc + mpicc build
│   ├── results.csv                  # final benchmark table
│   ├── report.html                  # full report with charts and screenshots
│   └── README.md                    # this file
├── ph2/                             # Hadoop MapReduce (in progress)
└── requirement.md
```

---

## Setup (one time)

### Windows

1. **MS-MPI runtime + SDK** — `winget install Microsoft.msmpi` and
   `winget install Microsoft.msmpisdk`. Verify with `mpiexec -help`.
2. **gcc** via MSYS2 — `winget install MSYS2.MSYS2`, then in the MSYS2 shell
   `pacman -S mingw-w64-x86_64-gcc`, then add `C:\msys64\mingw64\bin` to `PATH`.
3. **Python deps for the prep script** — `pip install pandas numpy`.

### Linux

1. **OpenMPI** — Fedora: `sudo dnf install openmpi openmpi-devel`.
   Debian/Ubuntu: `sudo apt install openmpi-bin libopenmpi-dev`. Arch: `sudo pacman -S openmpi`.
2. **gcc + make** — already there on most distros; if not:
   Fedora `sudo dnf install gcc make`, Debian `sudo apt install build-essential`.
3. **Put MPI on PATH** — on Fedora the OpenMPI binaries live under
   `/usr/lib64/openmpi/bin`, so load the module each shell:
   `module load mpi/openmpi-x86_64` (Debian/Arch put `mpicc`/`mpiexec` on PATH already).
4. **Python deps** — `pip install pandas numpy` (or `sudo dnf install python3-pandas python3-numpy`).

### macOS

1. **OpenMPI** — `brew install open-mpi`.
2. **Python deps** — `pip3 install pandas numpy`.

---

## Running it

Run everything from this `ph1/` directory. The dataset is one level up at
`../data/data.bin` (shared with ph2).

### Windows (PowerShell)

```powershell
python ..\data\prep.py                                   # ~30s, downloads + writes ..\data\data.bin
.\src\build.ps1                                          # compiles both .exe into bin\
.\bin\sequential.exe ..\data\data.bin                    # sequential baseline
mpiexec -n 4 .\bin\parallel_mpi.exe ..\data\data.bin     # 4-process MPI run
.\bench\benchmark.ps1                                    # full sweep, writes results.csv
```

### Linux / macOS

```bash
module load mpi/openmpi-x86_64                       # Fedora only; skip on Debian/Arch/macOS
python3 ../data/prep.py                              # ~30s, downloads + writes ../data/data.bin
make                                                 # builds bin/sequential + bin/parallel_mpi
./bin/sequential ../data/data.bin                    # sequential baseline
mpiexec -n 4 ./bin/parallel_mpi ../data/data.bin     # 4-process MPI run
./bench/benchmark.sh                                 # full sweep, writes results.csv
```

If you ask for more MPI ranks than physical cores, OpenMPI refuses by default;
`benchmark.sh` passes `--oversubscribe` automatically. For ad-hoc runs add it
yourself: `mpiexec --oversubscribe -n 8 ./bin/parallel_mpi data/data.bin`.

---

## Correctness

All five configurations produce **avg = 1.091615**, **min = 0.076**, **max = 11.122** —
matching NumPy in `data/data.meta.txt` exactly. `min` and `max` are bit-exact; `mean`
matches to within ~1e-9 because floating-point reduction order changes with process count.

---

## Findings

**1 · Memory-bandwidth-bound.** Each element costs ~2 instructions but one DRAM read.
At 16 MB the array does not fit in L3, so the loop is gated by memory bandwidth rather
than arithmetic. Adding more ranks on the same memory bus cannot buy more bandwidth.

**2 · Flat scaling from 2 → 8.** Median time at n = 2, 4 and 8 sits around 1.2 ms —
within run-to-run noise of each other. n = 8 is marginally **worse** because MPI
overhead grows while the bandwidth ceiling stays the same.

**3 · The n = 1 anomaly.** MPI at n = 1 is ~3× faster than `sequential.exe`, but it
is still one process. SIMD, loop type, cache effects, frequency, alignment and the
timing API were all ruled out. The only place this reproduces is via `benchmark.ps1`;
the most likely cause is hybrid-CPU P/E-core scheduling of `mpiexec` children on
Windows 11.

**The honest take.** This workload is memory-bandwidth-bound on a single machine, so
MPI scaling tops out near the bandwidth ceiling. A textbook linear speedup curve would
require either a multi-node cluster, or replacing the trivial reduction with per-element
compute (e.g. `sin(v) * cos(v)`).

### Measurement hygiene

- **Warmup pass** in both binaries so the timed region measures steady-state DRAM,
  not first-touch.
- **Disk I/O excluded** — `fread` runs before the timed region in both implementations.
- **Barrier before the timer** in MPI so no rank starts early.
- **Best of 15 runs** is the headline; Windows scheduling jitter is the main noise.

---

## Outputs / screenshots

`outputs/` contains real stdout captures (`*.txt`) from `sequential.exe`, the four MPI
runs, and `benchmark.ps1`, plus SVG terminal-style screenshots used by the report and
a small gallery at [`outputs/index.html`](outputs/index.html).

The full report — pipeline diagram, architecture flow, requirements checklist, results
charts, screenshots and findings — is in **[`report.html`](report.html)**.
