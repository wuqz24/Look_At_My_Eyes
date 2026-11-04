$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$reports=Join-Path $root 'reports'
New-Item -ItemType Directory -Path $reports -Force | Out-Null
Get-ChildItem -LiteralPath "$root/sim/build" -Filter 'tb_*.log' | Copy-Item -Destination $reports -Force
$files=@(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    $_.FullName -notlike "$root\sim\build*\*" -and $_.FullName -notlike "$root\xsim.dir\*" -and
    $_.FullName -notlike "$root\.Xil\*" -and
    $_.FullName -notlike "$root\vendor\td_rebuild\*" -and $_.FullName -notlike "$root\reports\*" -and
    $_.Extension -ne '.zip' -and $_.Name -notlike 'xvlog.*' -and $_.Name -notlike 'xelab.*' -and
    $_.Name -notlike 'td_*.log*' -and $_.Name -notlike 'webtalk*.log' -and $_.Extension -notin @('.wdb','.jou','.pb')
})
$files | ForEach-Object {
    [PSCustomObject]@{Path=$_.FullName.Substring($root.Length+1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
} | Export-Csv -LiteralPath "$reports/source_hashes.csv" -NoTypeInformation -Encoding UTF8
$out=Join-Path (Split-Path $root -Parent) ('HX1P35_Tracker_TD-ready_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.zip')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::Open($out,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($file in @($files)+@(Get-ChildItem -LiteralPath $reports -File)) {
        $name='HX1P35_Tracker/'+($file.FullName.Substring($root.Length+1) -replace '\\','/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$name,[IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $zip.Dispose() }
Write-Output "Created $out"
