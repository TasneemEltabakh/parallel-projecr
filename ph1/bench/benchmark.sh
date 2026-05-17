#!/usr/bin/env bash
# Linux/macOS port of benchmark.ps1.
# Runs sequential + mpi at several -n values, takes best of N runs,
# writes results.csv.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SEQ="$ROOT/bin/sequential"
MPI="$ROOT/bin/parallel_mpi"
DATA="${1:-$ROOT/../data/data.bin}"
REPEATS="${REPEATS:-15}"
PROCS=(${PROCS:-1 2 4 8})
OUT="$ROOT/results.csv"

for f in "$SEQ" "$MPI" "$DATA"; do
    [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }
done

# mpiexec must be on PATH; otherwise every MPI run produces no elapsed_ms
# line and the sweep collapses into a div-by-zero on speedup.
if ! command -v mpiexec >/dev/null 2>&1; then
    echo "mpiexec not found on PATH." >&2
    echo "Fedora: source /etc/profile.d/modules.sh && module load mpi/openmpi-x86_64" >&2
    echo "  or:   export PATH=/usr/lib64/openmpi/bin:\$PATH" >&2
    exit 1
fi

# Parse "elapsed_ms=NNN.NNN" from program output.
parse_ms() {
    awk -F'=' '/elapsed_ms=/ { print $2; exit }'
}

# Run cmd $REPEATS times (plus one warmup), echo "best median mean times-joined-by-;".
sweep() {
    local label="$1"; shift
    "$@" >/dev/null    # warmup
    local times=()
    for ((i = 0; i < REPEATS; i++)); do
        local t
        t="$("$@" | parse_ms)"
        if [[ -z "$t" ]]; then
            echo "no elapsed_ms in output of: $*" >&2
            echo "  (binary failed, or mpiexec refused to launch)" >&2
            exit 1
        fi
        times+=("$t")
    done

    # best / median / mean via awk
    local joined
    joined="$(IFS=';'; echo "${times[*]}")"
    local stats
    stats="$(printf '%s\n' "${times[@]}" | awk '
        { a[NR]=$1; s+=$1 }
        END {
            n=NR
            asort(a)
            best=a[1]
            mean=s/n
            med=(n%2)?a[int(n/2)+1]:(a[n/2]+a[n/2+1])/2
            printf "%.6f %.6f %.6f", best, med, mean
        }')"
    local best median mean
    read -r best median mean <<<"$stats"
    printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$best" "$median" "$mean" "$joined"
}

echo "sequential..."
seq_row="$(sweep sequential "$SEQ" "$DATA")"
IFS=$'\t' read -r _ seq_best seq_med seq_mean seq_times <<<"$seq_row"
printf '  best=%.3f median=%.3f mean=%.3f ms\n' "$seq_best" "$seq_med" "$seq_mean"

# Build CSV in memory; emit at the end.
csv_header='"impl","n_procs","time_ms","median_ms","mean_ms","speedup","all_times_ms"'
csv_rows=()
csv_rows+=("$(printf '"sequential","1","%.3f","%.3f","%s","1","%s"' \
    "$seq_best" "$seq_med" "$seq_mean" "$seq_times")")

for n in "${PROCS[@]}"; do
    echo "mpi -n $n..."
    # OpenMPI refuses to oversubscribe by default; allow it for sweeps that
    # exceed physical cores.
    row="$(sweep "mpi-n$n" mpiexec --oversubscribe -n "$n" "$MPI" "$DATA" 2>/dev/null \
           || sweep "mpi-n$n" mpiexec -n "$n" "$MPI" "$DATA")"
    IFS=$'\t' read -r _ best med mean times <<<"$row"
    sp="$(awk -v s="$seq_best" -v b="$best" 'BEGIN{printf "%.6f", s/b}')"
    printf '  best=%.3f median=%.3f mean=%.3f ms  speedup=%.2fx\n' "$best" "$med" "$mean" "$sp"
    csv_rows+=("$(printf '"mpi","%d","%.3f","%.3f","%s","%s","%s"' \
        "$n" "$best" "$med" "$mean" "$sp" "$times")")
done

{
    echo "$csv_header"
    printf '%s\n' "${csv_rows[@]}"
} > "$OUT"

echo
echo "wrote $OUT"
echo
column -t -s, "$OUT" 2>/dev/null || cat "$OUT"
