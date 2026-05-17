# PDC Project

Two-phase project on the UCI Household Power Consumption dataset (~2M rows).

| Phase | Stack | Status | Folder |
|-------|-------|--------|--------|
| 1 | C + MPI (sequential vs parallel) | Done | [`ph1/`](ph1/) |
| 2 | Hadoop MapReduce | In progress | `ph2/` |

The dataset lives once at [`data/`](data/) and is shared by both phases —
run `python3 data/prep.py` to download and prepare it.

Requirements for both phases are in [`requirement.md`](requirement.md).
