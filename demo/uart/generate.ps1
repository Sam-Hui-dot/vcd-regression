param([Parameter(Mandatory = $true)][string] $VivadoBin)
$ErrorActionPreference = 'Stop'
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
$scratch = Join-Path $PSScriptRoot '_build'
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$source = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'uart_tx.v')
$variants = [ordered]@{
    baseline = $source
    equivalent = $source.Replace('DATA_WIDTH+1', '1+DATA_WIDTH')
    faulty = $source.Replace("                txd_reg <= 1;", "                txd_reg <= 0;")
}
Push-Location $scratch
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'capture.tcl') -Destination .
    foreach ($variant in $variants.GetEnumerator()) {
        Set-Content -LiteralPath uart_variant.v -Value $variant.Value -Encoding ascii
        & (Join-Path $VivadoBin 'xvlog.bat') uart_variant.v (Join-Path $PSScriptRoot 'tb_uart.v')
        if ($LASTEXITCODE) { throw 'UART compile failed' }
        & (Join-Path $VivadoBin 'xelab.bat') -debug typical tb_uart -s $variant.Key
        if ($LASTEXITCODE) { throw 'UART elaboration failed' }
        $output = & (Join-Path $VivadoBin 'xsim.bat') $variant.Key -tclbatch capture.tcl
        $code = $LASTEXITCODE
        $output | Set-Content -LiteralPath ($variant.Key + '.log') -Encoding utf8
        if ($code -ne 0 -or ($output -join "`n") -match 'FAIL stimulus timeout') { throw 'UART simulation failed' }
        Copy-Item -LiteralPath trace.vcd -Destination (Join-Path $PSScriptRoot ($variant.Key + '.vcd'))
    }
} finally {
    Pop-Location
}
