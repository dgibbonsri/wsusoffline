<#
  Builds an ISO image (UDF file system) with IMAPI2, the disc-image service built into Windows.
  Replaces the external mkisofs.exe, so no third-party program is needed to create ISO images.

  -SourcePath   folder to put on the image (normally ..\client)
  -OutputFile   ISO file to create
  -VolumeName   volume label
  -ExcludeList  optional text file with one glob pattern per line (mkisofs -exclude-list style),
                matched case-insensitively against "../client/<path>" with forward slashes and
                against the plain file or folder name, e.g.  */w100/*   *ndp3*   *.au3

  Exit code 0 = success, 1 = error.
#>
param(
  [Parameter(Mandatory = $true)] [string] $SourcePath,
  [Parameter(Mandatory = $true)] [string] $OutputFile,
  [Parameter(Mandatory = $true)] [string] $VolumeName,
  [string] $ExcludeList
)
$ErrorActionPreference = 'Stop'

try {
  $source = (Resolve-Path -LiteralPath $SourcePath).ProviderPath.TrimEnd('\')
  $prefix = '../' + (Split-Path -Leaf $source) + '/'     # mkisofs saw paths like ../client/w100/...

  $patterns = @()
  if ($ExcludeList -and (Test-Path -LiteralPath $ExcludeList)) {
    $patterns = @(Get-Content -LiteralPath $ExcludeList | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
  }
  function Test-Excluded([string] $relPath, [string] $name) {
    $full = $prefix + $relPath.Replace('\', '/')
    foreach ($p in $patterns) {
      if ($full -like $p -or $name -like $p -or ($full + '/') -like $p) { return $true }
    }
    return $false
  }

  # Helper to copy IMAPI2's result stream into the .iso file (COM IStream -> file)
  if (-not ('WouIsoWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class WouIsoWriter {
  public static void Save(object imageStream, string path, int blockSize, long totalBlocks) {
    IStream src = (IStream)imageStream;
    byte[] buf = new byte[blockSize * 512];
    IntPtr pRead = Marshal.AllocHGlobal(sizeof(int));
    try {
      using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20)) {
        long remaining = (long)blockSize * totalBlocks;
        while (remaining > 0) {
          int want = (int)Math.Min((long)buf.Length, remaining);
          src.Read(buf, want, pRead);
          int got = Marshal.ReadInt32(pRead);
          if (got <= 0) throw new IOException("IMAPI2 image stream ended early");
          fs.Write(buf, 0, got);
          remaining -= got;
        }
      }
    } finally { Marshal.FreeHGlobal(pRead); }
  }
}
'@
  }

  $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
  $fsi.FileSystemsToCreate = 4            # UDF only: supports files larger than 4 GB
  $fsi.FreeMediaBlocks = 0                # no media size limit
  $fsi.VolumeName = $VolumeName
  $fsi.Root.AddTree($source, $false)

  # Remove excluded folders (whole tree) first, then excluded files in the remaining folders
  $removedDirs = New-Object System.Collections.Generic.List[string]
  $dirs = Get-ChildItem -LiteralPath $source -Recurse -Directory -Force | Sort-Object { $_.FullName.Length }
  foreach ($d in $dirs) {
    $rel = $d.FullName.Substring($source.Length + 1)
    if ($removedDirs | Where-Object { $rel.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }) { continue }
    if (Test-Excluded $rel $d.Name) { $fsi.Root.RemoveTree($rel); $removedDirs.Add($rel) }
  }
  $fileCount = 0; $excluded = 0
  foreach ($f in (Get-ChildItem -LiteralPath $source -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($source.Length + 1)
    if ($removedDirs | Where-Object { $rel.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }) { $excluded++; continue }
    if (Test-Excluded $rel $f.Name) { $fsi.Root.Remove($rel); $excluded++ } else { $fileCount++ }
  }

  Write-Host ("Writing {0} files to {1} ({2} excluded)..." -f $fileCount, $OutputFile, $excluded)
  $result = $fsi.CreateResultImage()
  [WouIsoWriter]::Save($result.ImageStream, $OutputFile, $result.BlockSize, $result.TotalBlocks)
  Write-Host ("Created {0} ({1:N0} bytes)" -f $OutputFile, (Get-Item -LiteralPath $OutputFile).Length)
  exit 0
}
catch {
  Write-Host ("ERROR: ISO image creation failed: {0}" -f $_.Exception.Message)
  exit 1
}
