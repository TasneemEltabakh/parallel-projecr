#!/usr/bin/env bash
# Hadoop equivalent of ph1/bench/benchmark.sh.
# Runs the MR job N times for each reducer count, takes best of N runs,
# writes results.csv with the same schema as Phase 1.
#
# Assumes the hadoop-pseudo container is up (see ../docker/run-cluster.sh)
# and the JAR is built (`make` in ph2/).

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd -- "$ROOT/.." && pwd)"
JAR_PATH="bin/phase2-mr.jar"
INPUT_HDFS="${INPUT_HDFS:-/input/data.txt}"
CONTAINER="${CONTAINER:-hadoop-pseudo}"
REPEATS="${REPEATS:-15}"
REDUCES=(${REDUCES:-1 2 4 8})
OUT="$ROOT/results.csv"
PH1_CSV="$ROOT/../ph1/results.csv"

# Sanity checks
[[ -f "$ROOT/$JAR_PATH" ]] || { echo "missing: $ROOT/$JAR_PATH (run make first)" >&2; exit 1; }
docker exec "$CONTAINER" hdfs dfs -test -e "$INPUT_HDFS" \
    || { echo "missing HDFS input: $INPUT_HDFS (run make put)" >&2; exit 1; }

run_one() {
    local n=$1
    docker exec -u hadoop -w /work/ph2 "$CONTAINER" \
        hadoop jar "$JAR_PATH" com.pdc.Driver \
        --input "$INPUT_HDFS" --output "/output/run" --reduces "$n" 2>&1 \
        | awk -F'=' '/^\[mr\] elapsed_ms=/ { print $2; exit }'
}

sweep() {
    local n=$1
    echo "  warmup..." >&2
    run_one "$n" >/dev/null
    local times=()
    for ((i = 0; i < REPEATS; i++)); do
        local t
        t="$(run_one "$n")"
        if [[ -z "$t" ]]; then
            echo "no elapsed_ms in MR output (reducers=$n)" >&2
            echo "  (container down? jar broken? check 'make logs')" >&2
            exit 1
        fi
        printf "  [%2d/%d] %s ms\n" $((i+1)) "$REPEATS" "$t" >&2
        times+=("$t")
    done
    local joined
    joined="$(IFS=';'; echo "${times[*]}")"
    local stats
    stats="$(printf '%s\n' "${times[@]}" | awk '
        { a[NR]=$1; s+=$1 }
        END {
            n=NR; asort(a)
            best=a[1]; mean=s/n
            med=(n%2)?a[int(n/2)+1]:(a[n/2]+a[n/2+1])/2
            printf "%.3f %.3f %.3f", best, med, mean
        }')"
    local best median mean
    read -r best median mean <<<"$stats"
    printf '%s\t%s\t%s\t%s\n' "$best" "$median" "$mean" "$joined"
}

# Hadoop@1 is our speedup baseline (sequential and MPI are orders of magnitude
# faster — meaningless to divide them in. They're appended as reference rows
# at the end of the CSV, not used as the speedup denominator.)
declare -A BEST MEDIAN MEAN TIMES
for n in "${REDUCES[@]}"; do
    echo "hadoop -reduces $n..."
    row="$(sweep "$n")"
    IFS=$'\t' read -r best med mean times <<<"$row"
    BEST[$n]=$best; MEDIAN[$n]=$med; MEAN[$n]=$mean; TIMES[$n]=$times
    printf "  -> best=%s median=%s mean=%s ms\n" "$best" "$med" "$mean"
done

base=${BEST[1]}

{
    echo '"impl","n_units","time_ms","median_ms","mean_ms","speedup","all_times_ms"'
    for n in "${REDUCES[@]}"; do
        sp="$(awk -v b="$base" -v x="${BEST[$n]}" 'BEGIN{printf "%.6f", b/x}')"
        printf '"hadoop","%d","%s","%s","%s","%s","%s"\n' \
            "$n" "${BEST[$n]}" "${MEDIAN[$n]}" "${MEAN[$n]}" "$sp" "${TIMES[$n]}"
    done
    if [[ -f "$PH1_CSV" ]]; then
        echo '"# ---- phase 1 reference (sequential + best MPI) ----","","","","","",""'
        # sequential row + best MPI row from phase 1
        awk -F',' 'NR>1 && ($1=="\"sequential\"" || $1=="\"mpi\"")' "$PH1_CSV" \
            | awk -F',' '
                { rows[NR]=$0 }
                END {
                    # print sequential row as-is, then find best MPI row (min time_ms)
                    bestRow=""; bestT=1e30
                    for (i=1; i<=NR; i++) {
                        split(rows[i], f, ",")
                        if (f[1]=="\"sequential\"") print rows[i]
                        else if (f[1]=="\"mpi\"") {
                            gsub("\"","",f[3]); t=f[3]+0
                            if (t < bestT) { bestT=t; bestRow=rows[i] }
                        }
                    }
                    if (bestRow!="") print bestRow
                }'
    fi
} > "$OUT"

echo
echo "wrote $OUT"
echo
column -t -s, "$OUT" 2>/dev/null | head -10 || cat "$OUT"
