# PDC Project — Phase 1

Sequential vs MPI on the UCI Household Power Consumption dataset (~2M rows).
Both programs compute avg / min / max of `Global_active_power` in one pass.

## Files

```
data/prep.py          downloads the dataset, writes data.bin (float64)
src/sequential.c      single-process baseline
src/parallel_mpi.c    MPI version (MPI_Scatterv + MPI_Reduce)
src/build.ps1         gcc + MS-MPI linkage
bench/benchmark.ps1   runs everything, writes results.csv
```

## Setup (one time)

1. Install MS-MPI: run `msmpisetup.exe` and `msmpisdk.msi` from Microsoft. Check with `mpiexec -help`.
2. Install gcc — easiest via MSYS2 (`winget install MSYS2.MSYS2`, then `pacman -S mingw-w64-x86_64-gcc` and add `C:\msys64\mingw64\bin` to PATH).
3. `pip install pandas numpy` for the prep script.

## Running it

```powershell
python data\prep.py            # ~30s, downloads + writes data.bin
.\src\build.ps1                # compiles both .exe into bin\
.\bin\sequential.exe .\data\data.bin
mpiexec -n 4 .\bin\parallel_mpi.exe .\data\data.bin
.\bench\benchmark.ps1          # full sweep at N=1,2,4,8
```

## Correctness

`data/data.meta.txt` has the NumPy reference for sum / mean / min / max.
The C programs should match min / max exactly and mean within ~1e-9
(floating-point reduction order changes with process count).
