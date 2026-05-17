# Hadoop equivalent of ph1/bench/benchmark.ps1.
# Drives the MR job through `docker exec` and writes results.csv with
# the same schema as Phase 1.
# Assumes the hadoop-pseudo container is up and the JAR is built.

param(
    [int[]] $Reduces   = @(1, 2, 4, 8),
    [int]   $Repeats   = 15,
    [string]$Container = "hadoop-pseudo",
    [string]$InputHdfs = "/input/data.txt"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$jar  = "bin/phase2-mr.jar"
$ph1Csv = Join-Path $root "..\ph1\results.csv"

if (-not (Test-Path (Join-Path $root $jar))) {
    throw "missing JAR: $root\$jar (run make in ph2/ first)"
}

function Run-One($n) {
    $out = docker exec -u hadoop -w /work/ph2 $Container `
        hadoop jar $jar com.pdc.Driver `
        --input $InputHdfs --output /output/run --reduces $n 2>&1
    foreach ($line in $out) {
        if ($line -match '^\[mr\] elapsed_ms=([0-9.]+)') {
            return [double]$Matches[1]
        }
    }
    throw "no elapsed_ms found in output"
}

function Sweep($n) {
    Run-One $n | Out-Null   # warmup
    $ts = @()
    for ($i = 0; $i -lt $Repeats; $i++) {
        $t = Run-One $n
        Write-Host ("  [{0,2}/{1}] {2} ms" -f ($i + 1), $Repeats, $t)
        $ts += $t
    }
    [pscustomobject]@{
        best   = ($ts | Measure-Object -Minimum).Minimum
        median = ($ts | Sort-Object)[[int]($ts.Count / 2)]
        mean   = ($ts | Measure-Object -Average).Average
        times  = $ts
    }
}

$rows = @()
foreach ($n in $Reduces) {
    Write-Host "hadoop -reduces $n..."
    $r = Sweep $n
    Write-Host ("  -> best={0:N3} median={1:N3} mean={2:N3} ms" -f $r.best, $r.median, $r.mean)
    $rows += [pscustomobject]@{
        impl   = "hadoop"
        n_units = $n
        time_ms = $r.best
        median_ms = $r.median
        mean_ms = $r.mean
        # speedup vs hadoop@1
        speedup = if ($n -eq $Reduces[0]) { 1.0 } else { $rows[0].time_ms / $r.best }
        all_times_ms = ($r.times -join ";")
    }
}

$out = Join-Path $root "results.csv"
$rows | Export-Csv -Path $out -NoTypeInformation

# Append phase 1 reference rows: sequential + best-time MPI.
if (Test-Path $ph1Csv) {
    $ph1 = Import-Csv $ph1Csv
    $seq = $ph1 | Where-Object { $_.impl -eq "sequential" } | Select-Object -First 1
    $bestMpi = $ph1 | Where-Object { $_.impl -eq "mpi" } | Sort-Object { [double]$_.time_ms } | Select-Object -First 1
    Add-Content $out '"# ---- phase 1 reference (sequential + best MPI) ----","","","","","",""'
    $seq, $bestMpi | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Add-Content $out
}

Write-Host "wrote $out"
$rows | Format-Table impl, n_units,
    @{Label="best_ms";   Expression={"{0:N3}" -f $_.time_ms}},
    @{Label="median_ms"; Expression={"{0:N3}" -f $_.median_ms}},
    @{Label="mean_ms";   Expression={"{0:N3}" -f $_.mean_ms}},
    @{Label="speedup";   Expression={"{0:N2}x" -f $_.speedup}}
