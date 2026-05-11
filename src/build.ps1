# compiles sequential.exe and parallel_mpi.exe into ../bin
# needs: gcc on PATH, MS-MPI SDK installed

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root "src"
$bin  = Join-Path $root "bin"

if (-not (Test-Path $bin)) { New-Item -ItemType Directory -Path $bin | Out-Null }

# MS-MPI SDK location. MSMPI_INC points at ...\Include if it's set.
if ($env:MSMPI_INC) {
    $sdk = Split-Path -Parent $env:MSMPI_INC
} else {
    $sdk = "C:\Program Files (x86)\Microsoft SDKs\MPI"
}
$inc = Join-Path $sdk "Include"
$lib = Join-Path $sdk "Lib\x64"

if (-not (Test-Path $inc)) { throw "MS-MPI Include not found at $inc" }
if (-not (Test-Path $lib)) { throw "MS-MPI Lib not found at $lib" }

Write-Host "building sequential..."
gcc (Join-Path $src "sequential.c") -O2 -o (Join-Path $bin "sequential.exe")
if ($LASTEXITCODE -ne 0) { throw "sequential build failed" }

Write-Host "building parallel..."
gcc (Join-Path $src "parallel_mpi.c") -O2 -I"$inc" -L"$lib" -lmsmpi -o (Join-Path $bin "parallel_mpi.exe")
if ($LASTEXITCODE -ne 0) { throw "parallel build failed" }

Write-Host "done. binaries in $bin"
