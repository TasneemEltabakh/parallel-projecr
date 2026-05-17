# Download the UCI Household Power Consumption dataset and dump the
# Global_active_power column as a flat float64 file so the C programs
# can just fread it.

import sys
import time
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

URL = "https://archive.ics.uci.edu/ml/machine-learning-databases/00235/household_power_consumption.zip"
COL = "Global_active_power"

HERE = Path(__file__).resolve().parent
ZIP  = HERE / "household_power_consumption.zip"
CSV  = HERE / "household_power_consumption.txt"
BIN  = HERE / "data.bin"
TXT  = HERE / "data.txt"   # ph2 (Hadoop) input: one float per line
META = HERE / "data.meta.txt"


def fetch():
    if CSV.exists():
        print(f"[prep] {CSV.name} already there, skipping download")
        return
    print(f"[prep] downloading {URL}")
    t0 = time.time()
    urllib.request.urlretrieve(URL, ZIP)
    print(f"[prep] got {ZIP.stat().st_size / 1e6:.1f} MB in {time.time() - t0:.1f}s")
    with zipfile.ZipFile(ZIP) as z:
        z.extract(CSV.name, HERE)


def build():
    print(f"[prep] reading {CSV.name}")
    df = pd.read_csv(CSV, sep=";", usecols=[COL], na_values=["?"], low_memory=False)
    raw = len(df)
    s = pd.to_numeric(df[COL], errors="coerce").dropna()
    n = len(s)
    print(f"[prep] {raw:,} rows -> {n:,} after dropping NaN")

    arr = s.to_numpy(dtype=np.float64, copy=False)
    arr.tofile(BIN)
    print(f"[prep] wrote {BIN.name} ({BIN.stat().st_size / 1e6:.1f} MB)")

    # ph2 also wants a text form: one float per line, no header.
    # Skip if up-to-date with the CSV.
    if TXT.exists() and TXT.stat().st_mtime >= CSV.stat().st_mtime:
        print(f"[prep] {TXT.name} up-to-date, skipping")
    else:
        np.savetxt(TXT, arr, fmt="%.3f")
        print(f"[prep] wrote {TXT.name} ({TXT.stat().st_size / 1e6:.1f} MB)")

    # reference values so we can sanity-check the C output
    META.write_text(
        f"n={n}\n"
        f"dtype=float64\n"
        f"column={COL}\n"
        f"source={URL}\n"
        f"sum={float(arr.sum()):.6f}\n"
        f"min={float(arr.min()):.6f}\n"
        f"max={float(arr.max()):.6f}\n"
        f"mean={float(arr.mean()):.6f}\n"
    )
    print(f"[prep] meta -> {META.name}")
    return n


if __name__ == "__main__":
    fetch()
    n = build()
    if n < 100_000:
        sys.exit(f"only {n} rows, need at least 100k")
    print(f"[prep] done. {n:,} doubles in {BIN}")
