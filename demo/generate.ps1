param([Parameter(Mandatory = $true)][string] $VivadoBin)
$ErrorActionPreference = 'Stop'
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$scratch = Join-Path $PSScriptRoot '_build'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$rtl = @('btn_debounce.v', 'counter_mod.v', 'dynamic_display.v', 'edge_detect.v', 'hex_counter_top.v', 'tb_hex_counter_top.v')
$files = @($rtl | ForEach-Object { Join-Path $PSScriptRoot $_ })
$original = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'counter_mod.v')
$variants = [ordered]@{
    baseline = $original
    equivalent = $original.Replace("count + 1'b1", "count + 4'd1")
    faulty = $original.Replace("MOD - 5'd1", "MOD - 5'd2")
}
Push-Location $scratch
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'capture.tcl') -Destination .
    & (Join-Path $VivadoBin 'xvlog.bat') @files
    if ($LASTEXITCODE) { throw 'RTL compile failed' }
    foreach ($variant in $variants.GetEnumerator()) {
        Set-Content -LiteralPath counter_variant.v -Value $variant.Value -Encoding ascii
        & (Join-Path $VivadoBin 'xvlog.bat') counter_variant.v
        if ($LASTEXITCODE) { throw 'Counter compile failed' }
        & (Join-Path $VivadoBin 'xelab.bat') -debug typical -timescale 1ns/1ps tb_hex_counter_top -s $variant.Key
        if ($LASTEXITCODE) { throw 'Elaboration failed' }
        & (Join-Path $VivadoBin 'xsim.bat') $variant.Key -tclbatch capture.tcl
        if ($LASTEXITCODE) { throw 'Simulation failed' }
        Copy-Item -LiteralPath trace.vcd -Destination (Join-Path $PSScriptRoot ($variant.Key + '.vcd'))
    }
} finally {
    Pop-Location
}
