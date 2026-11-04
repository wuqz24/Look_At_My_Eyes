param(
    [switch]$CleanGenerated
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\')
$rootPrefix = $root + '\'
$targets = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()

function Add-Target([System.IO.FileSystemInfo]$item) {
    $full = [IO.Path]::GetFullPath($item.FullName)
    if($full -ne $root -and !$full.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside project root: $full"
    }
    if(!($targets | Where-Object FullName -eq $item.FullName)) { [void]$targets.Add($item) }
}

foreach($name in @('.Xil','xsim.dir')) {
    $path = Join-Path $root $name
    if(Test-Path -LiteralPath $path) { Add-Target (Get-Item -LiteralPath $path) }
}

$sim = Join-Path $root 'sim'
if(Test-Path -LiteralPath $sim) {
    Get-ChildItem -LiteralPath $sim -Directory -Filter 'build*' | ForEach-Object { Add-Target $_ }
}

foreach($pattern in @('*.wdb','*.jou','*.pb','td_*.log*','webtalk*.log','xelab.log','xvlog.log')) {
    Get-ChildItem -LiteralPath $root -File -Filter $pattern | ForEach-Object { Add-Target $_ }
}

if($targets.Count -eq 0) {
    Write-Output 'No generated files or directories matched.'
    exit 0
}

Write-Output "Generated items matched: $($targets.Count)"
$targets | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($root.Length + 1)
    if($CleanGenerated) {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
        Write-Output "REMOVED $relative"
    } else {
        Write-Output "DRY-RUN $relative"
    }
}

if(!$CleanGenerated) {
    Write-Output 'Dry-run only. Re-run with -CleanGenerated to remove the listed items.'
} else {
    Write-Output 'Generated-item cleanup complete. Source, constraints, reports, TD runs and bit files were not targeted.'
}
