# PDC Project

**Team:** Aser Osama (202101266) · Tasneem Muhammed (202101031) · Marwan Ahmed (202101214) · Rghda Salah (202101510) · Mohamed Magdy (202101520)

Two-phase project on the UCI Household Power Consumption dataset (~2M rows).

| Phase | Stack | Status | Folder |
|-------|-------|--------|--------|
| 1 | C + MPI (sequential vs parallel) | Done | [`ph1/`](ph1/) |
| 2 | Hadoop MapReduce (Java, pseudo-distributed in Docker) | Done | [`ph2/`](ph2/) |

The dataset lives once at [`data/`](data/) and is shared by both phases.
Run `python3 data/prep.py` to download and prepare it — it writes both
`data/data.bin` (Phase 1, flat float64) and `data/data.txt` (Phase 2, one
float per line, HDFS-friendly).

Each phase has its own README with setup, build, and run instructions.
The headline benchmark tables are in `ph1/results.csv` and `ph2/results.csv`.

- **5 min · scroll-snap slide deck**: [`presentation.html`](presentation.html) —
  7 slides, big text, arrow-key nav. Use this for the live discussion.
- **10 min · scrolling write-up**: [`final_report.html`](final_report.html) —
  same content with more detail and a sticky sidebar nav.

Requirements for both phases are in [`requirement.md`](requirement.md).
