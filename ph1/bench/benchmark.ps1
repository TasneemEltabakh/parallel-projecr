# Runs sequential.exe and parallel_mpi.exe a bunch of times each and
# writes the timings to results.csv. Takes the best run because
# Windows scheduling jitter is the main noise source.

param(
    [int[]] $ProcCounts = @(1, 2, 4, 8),
    [int]   $Repeats    = 15,
    [string]$DataPath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$seq  = Join-Path $root "bin\sequential.exe"
$mpi  = Join-Path $root "bin\parallel_mpi.exe"
if (-not $DataPath) { $DataPath = Join-Path $root "..\data\data.bin" }

foreach ($p in @($seq, $mpi, $DataPath)) {
    if (-not (Test-Path $p)) { throw "missing: $p" }
}

function Parse-Ms($lines) {
    foreach ($l in $lines) {
        if ($l -match 'elapsed_ms=([0-9.]+)') { return [double]$Matches[1] }
    }
    throw "no elapsed_ms in output"
}

function Sweep($cmd, $n) {
    # one warmup run so file-cache / branch predictor are hot
    & $cmd | Out-Null
    $ts = @()
    for ($i = 0; $i -lt $n; $i++) {
        $ts += Parse-Ms (& $cmd)
    }
    [pscustomobject]@{
        best   = ($ts | Measure-Object -Minimum).Minimum
        median = ($ts | Sort-Object)[[int]($ts.Count / 2)]
        mean   = ($ts | Measure-Object -Average).Average
        times  = $ts
    }
}

Write-Host "sequential..."
$s = Sweep { & $seq $DataPath } $Repeats
Write-Host ("  best={0:N3} median={1:N3} mean={2:N3} ms" -f $s.best, $s.median, $s.mean)

$rows = @([pscustomobject]@{
    impl="sequential"; n_procs=1
    time_ms=$s.best; median_ms=$s.median; mean_ms=$s.mean
    speedup=1.0
    all_times_ms=($s.times -join ";")
})

foreach ($n in $ProcCounts) {
    Write-Host "mpi -n $n..."
    $r = Sweep { & mpiexec -n $n $mpi $DataPath } $Repeats
    $sp = $s.best / $r.best
    Write-Host ("  best={0:N3} median={1:N3} mean={2:N3} ms  speedup={3:N2}x" -f $r.best, $r.median, $r.mean, $sp)
    $rows += [pscustomobject]@{
        impl="mpi"; n_procs=$n
        time_ms=$r.best; median_ms=$r.median; mean_ms=$r.mean
        speedup=$sp
        all_times_ms=($r.times -join ";")
    }
}

$out = Join-Path $root "results.csv"
$rows | Export-Csv -Path $out -NoTypeInformation
Write-Host "wrote $out"

Write-Host ""
$rows | Format-Table impl, n_procs,
    @{Label="best_ms";   Expression={"{0:N3}" -f $_.time_ms}},
    @{Label="median_ms"; Expression={"{0:N3}" -f $_.median_ms}},
    @{Label="mean_ms";   Expression={"{0:N3}" -f $_.mean_ms}},
    @{Label="speedup";   Expression={"{0:N2}x" -f $_.speedup}}
