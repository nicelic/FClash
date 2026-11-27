param(
  [Parameter(Mandatory = $true)][string]$Arch,
  [Parameter(Mandatory = $true)][string]$DistDir,
  [Parameter(Mandatory = $true)][string]$ChecksumFile
)

$ErrorActionPreference = 'Stop'

function Get-PeMachine([string]$FilePath) {
  $fs = [System.IO.File]::OpenRead($FilePath)
  try {
    $br = New-Object System.IO.BinaryReader($fs)
    if ($br.ReadUInt16() -ne 0x5A4D) {
      throw "Invalid MZ header: $FilePath"
    }
    $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
    $peOffset = $br.ReadInt32()
    $fs.Seek($peOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
    if ($br.ReadUInt32() -ne 0x00004550) {
      throw "Invalid PE signature: $FilePath"
    }
    return $br.ReadUInt16()
  } finally {
    $fs.Dispose()
  }
}

$expectedMachine = switch ($Arch) {
  'amd64' { 0x8664 }
  'arm64' { 0xAA64 }
  default { throw "Unsupported Windows arch: $Arch" }
}

$exes = @(Get-ChildItem -Path $DistDir -File -Filter '*.exe')
$zips = @(Get-ChildItem -Path $DistDir -File -Filter '*.zip')

if ($exes.Count -ne 1 -or $zips.Count -ne 1) {
  throw "Expected 1 .exe and 1 .zip in $DistDir (found $($exes.Count) exe, $($zips.Count) zip)"
}

$exe = $exes[0]
$zip = $zips[0]
if ($exe.Length -lt 5MB -or $zip.Length -lt 5MB) {
  throw "Artifact too small: exe=$($exe.Length), zip=$($zip.Length)"
}

[void](Get-PeMachine $exe.FullName)

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("flclash-verify-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Expand-Archive -Path $zip.FullName -DestinationPath $tmp -Force

  $required = @(
    'FlClash.exe',
    'FlClashCore.exe',
    'FlClashHelperService.exe',
    'EnableLoopback.exe',
    'manifest.json',
    'rust_api.dll'
  )
  foreach ($name in $required) {
    $found = Get-ChildItem -Path $tmp -Recurse -File -Filter $name | Select-Object -First 1
    if (-not $found) {
      throw "Windows zip missing required file: $name"
    }
  }

  foreach ($peName in @('FlClash.exe', 'FlClashCore.exe', 'FlClashHelperService.exe', 'rust_api.dll')) {
    $bin = Get-ChildItem -Path $tmp -Recurse -File -Filter $peName | Select-Object -First 1
    $machine = Get-PeMachine $bin.FullName
    if ($machine -ne $expectedMachine) {
      throw ("PE machine mismatch for {0}: expected 0x{1:X4}, got 0x{2:X4}" -f $peName, $expectedMachine, $machine)
    }
  }

  $coreBin = Get-ChildItem -Path $tmp -Recurse -File -Filter 'FlClashCore.exe' | Select-Object -First 1
  $manifestFile = Get-ChildItem -Path $tmp -Recurse -File -Filter 'manifest.json' | Select-Object -First 1
  $manifest = Get-Content -Path $manifestFile.FullName -Raw | ConvertFrom-Json
  $actualHash = (Get-FileHash -Path $coreBin.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($manifest.coreSha256 -ne $actualHash) {
    throw "Core SHA256 mismatch: manifest=$($manifest.coreSha256), actual=$actualHash"
  }
} finally {
  Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$checksumDir = Split-Path -Parent $ChecksumFile
if ($checksumDir) {
  New-Item -ItemType Directory -Path $checksumDir -Force | Out-Null
}

$lines = foreach ($item in @($exe, $zip) | Sort-Object Name) {
  $hash = (Get-FileHash -Path $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $($item.Name)"
}
[System.IO.File]::WriteAllText(
  $ChecksumFile,
  (($lines -join "`n") + "`n"),
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Verified windows ($Arch) artifacts:"
Get-Content -Path $ChecksumFile
