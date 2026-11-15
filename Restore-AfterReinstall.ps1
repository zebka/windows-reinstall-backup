# Restore-AfterReinstall.ps1  (interactive restore for backups made by Backup-BeforeReinstall.ps1)
# Keys: Up/Down = move | Space = tick | A = all/none | Enter = continue | Esc = quit
# Optional: -Source "E:\Backup_PCNAME_20261108_1019" to skip backup detection
# Existing files are NEVER overwritten (except browser bookmark files, which are renamed to *.before-restore first).

param([string]$Source = "")

# --- self-elevate to Administrator ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Source) { $a += " -Source `"$Source`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    exit
}

$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Restore after Windows reinstall'
$pcName = $env:COMPUTERNAME
$W      = [Math]::Max(70, $Host.UI.RawUI.WindowSize.Width - 1)
$FULL   = [string][char]0x2588
$EMPTY  = [string][char]0x2591

# ---------------- helpers ----------------
function Fmt([int64]$b) {
    if ($b -ge 1GB) { '{0:N2} GB' -f ($b/1GB) }
    elseif ($b -ge 1MB) { '{0:N1} MB' -f ($b/1MB) }
    else { '{0:N0} KB' -f ($b/1KB) }
}
function Line([string]$t = '', $fg = 'Gray') {
    if ($t.Length -gt $W) { $t = $t.Substring(0, $W) } else { $t = $t.PadRight($W) }
    Write-Host $t -ForegroundColor $fg
}
function Bar([double]$frac, [int]$len = 40) {
    $frac = [Math]::Min(1, [Math]::Max(0, $frac))
    $f = [int][Math]::Floor($frac * $len)
    ($FULL * $f) + ($EMPTY * ($len - $f))
}
function Banner([string]$sub) {
    Line ('=' * $W) Cyan
    Line "  WINDOWS RESTORE    PC: $pcName    $(Get-Date -Format 'yyyy-MM-dd HH:mm')" White
    if ($sub) { Line "  $sub" DarkCyan }
    Line ('=' * $W) Cyan
}
function DirSize($p) {
    [int64](Get-ChildItem $p -Recurse -File -Force | Measure-Object Length -Sum).Sum
}
function NewItem($name, $kind, $checked) {
    [pscustomobject]@{ Name = $name; Kind = $kind; Jobs = @(); Files = @(); Size = [int64]0; Checked = $checked }
}
function AddJob($it, $src, $dst) {
    $it.Jobs += [pscustomobject]@{ Src = $src; Dst = $dst; Size = [int64]0 }
}
# Real location of a user folder on the NEW Windows (handles OneDrive redirection for the current user)
function TargetFolder($user, $name) {
    if ($user -eq $env:USERNAME) {
        $p = switch ($name) {
            'Desktop'   { [Environment]::GetFolderPath('Desktop') }
            'Documents' { [Environment]::GetFolderPath('MyDocuments') }
            'Pictures'  { [Environment]::GetFolderPath('MyPictures') }
            'Videos'    { [Environment]::GetFolderPath('MyVideos') }
            'Music'     { [Environment]::GetFolderPath('MyMusic') }
            'Downloads' { (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path }
        }
        if ($p) { return $p }
    }
    return "C:\Users\$user\$name"
}

# ---------------- 1) Find the backup ----------------
[Console]::CursorVisible = $true
Clear-Host
Banner 'Step 1/4  Locate backup'
if (-not $Source) {
    $found = @()
    foreach ($d in (Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 -or $_.DriveType -eq 3 })) {
        Get-ChildItem ($d.DeviceID + '\') -Directory -Filter 'Backup_*' -Force | ForEach-Object { $found += $_ }
    }
    $found = @($found | Sort-Object LastWriteTime -Descending)
    if (-not $found.Count) {
        Line '  No Backup_* folder found on any drive. Connect the backup drive and run again,' Red
        Line '  or run:  .\Restore-AfterReinstall.ps1 -Source "E:\Backup_..."' Red
        Read-Host 'Press Enter to exit'; exit 1
    }
    if ($found.Count -eq 1) { $Source = $found[0].FullName }
    else {
        Line '  Backups found:' White
        for ($i = 0; $i -lt $found.Count; $i++) { Line ("   [{0}] {1}   ({2})" -f ($i + 1), $found[$i].FullName, $found[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm')) Gray }
        $n = Read-Host '  Choose number'
        $idx = 0; [void][int]::TryParse($n, [ref]$idx)
        if ($idx -lt 1 -or $idx -gt $found.Count) { exit }
        $Source = $found[$idx - 1].FullName
    }
}
Line ("  Using backup: {0}" -f $Source) Green
Line ''

# ---------------- 2) Map backup users -> Windows users ----------------
$oldUsers = @(Get-ChildItem (Join-Path $Source 'Users') -Directory)
$map = @{}
$existing = (Get-ChildItem 'C:\Users' -Directory -Force | Where-Object { @('Public', 'Default', 'Default User', 'All Users') -notcontains $_.Name }).Name
Line ("  Windows users on this PC: {0}" -f ($existing -join ', ')) DarkGray
foreach ($ou in $oldUsers) {
    $def = if ($existing -contains $ou.Name) { $ou.Name } else { $env:USERNAME }
    $ans = Read-Host ("  Backup user '{0}' -> restore into Windows user [{1}]" -f $ou.Name, $def)
    if ($ans) { $def = $ans }
    if ($existing -notcontains $def) { Line "  '$def' has no profile here, using $env:USERNAME" Yellow; $def = $env:USERNAME }
    $map[$ou.Name] = $def
}
$firstTarget = if ($map.Count) { ($map.Values | Select-Object -First 1) } else { $env:USERNAME }
$restoredRoot = Join-Path (TargetFolder $firstTarget 'Documents') 'Restored-Backup'

# ---------------- 3) Build items ----------------
[Console]::CursorVisible = $false
Clear-Host
Banner 'Step 2/4  Scanning backup'
$items = New-Object System.Collections.ArrayList

foreach ($f in 'Desktop', 'Downloads', 'Documents', 'Pictures', 'Videos', 'Music') {
    $it = NewItem $f 'folders' ($f -ne 'Music')
    foreach ($ou in $oldUsers) {
        $dst = TargetFolder $map[$ou.Name] $f
        $p = Join-Path $ou.FullName $f
        if (Test-Path $p) { AddJob $it $p $dst }
        foreach ($od in (Get-ChildItem $ou.FullName -Directory -Filter 'OneDrive*' -Force)) {
            $p2 = Join-Path $od.FullName $f
            if (Test-Path $p2) { AddJob $it $p2 $dst }
        }
    }
    if ($it.Jobs.Count) { [void]$items.Add($it) }
}

# Browser bookmarks
$bm = NewItem 'Browser bookmarks (Chrome / Edge / Brave / Firefox) - close browsers first' 'files' $true
$bRoot = Join-Path $Source 'Browsers'
foreach ($bu in (Get-ChildItem $bRoot -Directory)) {
    $t = $map[$bu.Name]; if (-not $t) { $t = $env:USERNAME }
    foreach ($pd in (Get-ChildItem $bu.FullName -Directory)) {
        $parts = $pd.Name -split '_', 2
        $b = $parts[0]; $prof = $parts[1]
        $base = switch ($b) {
            'Chrome' { 'AppData\Local\Google\Chrome\User Data' }
            'Edge'   { 'AppData\Local\Microsoft\Edge\User Data' }
            'Brave'  { 'AppData\Local\BraveSoftware\Brave-Browser\User Data' }
        }
        if ($b -eq 'Firefox') {
            $ffRoot = "C:\Users\$t\AppData\Roaming\Mozilla\Firefox\Profiles"
            $p2 = Get-ChildItem $ffRoot -Directory | Where-Object { $_.Name -like '*.default-release' } | Select-Object -First 1
            $dstDir = if ($p2) { $p2.FullName } else { Join-Path $restoredRoot "Browsers\Firefox_$prof" }
        } elseif ($base) { $dstDir = "C:\Users\$t\$base\$prof" }
        else { continue }
        foreach ($file in (Get-ChildItem $pd.FullName -File)) {
            $bm.Files += [pscustomobject]@{ Src = $file.FullName; Dst = $dstDir }
            $bm.Size += $file.Length
        }
    }
}
if ($bm.Files.Count) { [void]$items.Add($bm) }

# Outlook / Sticky notes -> Restored-Backup (manual import)
foreach ($ou in $oldUsers) {
    $docs = Join-Path (TargetFolder $map[$ou.Name] 'Documents') 'Restored-Backup'
    $p = Join-Path $ou.FullName 'OutlookData'
    if (Test-Path $p) { $it = NewItem "Outlook data of $($ou.Name) -> Documents\Restored-Backup" 'folders' $true; AddJob $it $p (Join-Path $docs "Outlook-$($ou.Name)"); [void]$items.Add($it) }
    $p = Join-Path $ou.FullName 'StickyNotes'
    if (Test-Path $p) { $it = NewItem "Sticky Notes of $($ou.Name) -> Documents\Restored-Backup" 'folders' $false; AddJob $it $p (Join-Path $docs "StickyNotes-$($ou.Name)"); [void]$items.Add($it) }
}

# Wi-Fi + system info
$sysDir = Join-Path $Source 'SystemInfo'
if (Test-Path $sysDir) {
    $wf = NewItem 'Wi-Fi networks (import saved profiles and passwords)' 'wifi' $true
    foreach ($x in (Get-ChildItem $sysDir -Filter '*.xml')) { $wf.Files += [pscustomobject]@{ Src = $x.FullName; Dst = '' }; $wf.Size += $x.Length }
    if ($wf.Files.Count) { [void]$items.Add($wf) }
    $si = NewItem 'System info (program list, printers) -> Documents\Restored-Backup' 'folders' $true
    AddJob $si $sysDir (Join-Path $restoredRoot 'SystemInfo')
    [void]$items.Add($si)
}

# Custom folders
$cDir = Join-Path $Source 'Custom'
foreach ($cd in (Get-ChildItem $cDir -Directory)) {
    $it = NewItem "Custom: $($cd.Name) -> Documents\Restored-Backup" 'folders' $true
    AddJob $it $cd.FullName (Join-Path $restoredRoot "Custom\$($cd.Name)")
    [void]$items.Add($it)
}

# Measure sizes with progress
$allJobs = @(); foreach ($it in $items) { foreach ($j in $it.Jobs) { $allJobs += [pscustomobject]@{ Item = $it; Job = $j } } }
$top = [Console]::CursorTop + 1
$k = 0
foreach ($x in $allJobs) {
    [Console]::SetCursorPosition(0, $top)
    $frac = $k / [Math]::Max(1, $allJobs.Count)
    Line ("  Measuring sizes...  {0} / {1}" -f $k, $allJobs.Count) Yellow
    Line ("  [{0}] {1,3}%" -f (Bar $frac 50), [int]($frac * 100)) Green
    Line ("  " + $x.Job.Src) DarkGray
    $x.Job.Size = DirSize $x.Job.Src
    $x.Item.Size += $x.Job.Size
    $k++
}

# ---------------- 4) Checkbox menu ----------------
$cur = 0
$nameW = $W - 20
Clear-Host
while ($true) {
    [Console]::SetCursorPosition(0, 0)
    Banner 'Step 3/4  Choose what to restore'
    Line '  Up/Down: move   Space: tick   A: all/none   Enter: continue   Esc: quit' DarkGray
    Line ''
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $bg = if ($i -eq $cur) { 'DarkGray' } else { $null }
        $name = $it.Name; if ($name.Length -gt $nameW) { $name = $name.Substring(0, $nameW - 3) + '...' }
        $sizeColor = if ($it.Size -ge 20GB) { 'Red' } elseif ($it.Size -ge 5GB) { 'Yellow' } else { 'Gray' }
        $pre = if ($i -eq $cur) { '> ' } else { '  ' }
        $args1 = @{ NoNewline = $true }; if ($bg) { $args1.BackgroundColor = $bg }
        Write-Host $pre @args1
        if ($it.Checked) { Write-Host '[x]' -ForegroundColor Green @args1 } else { Write-Host '[ ]' -ForegroundColor DarkGray @args1 }
        Write-Host (' ' + $name.PadRight($nameW)) -ForegroundColor White @args1
        Write-Host ((Fmt $it.Size).PadLeft(11)) -ForegroundColor $sizeColor @args1
        $rest = $W - (2 + 3 + 1 + $nameW + 11)
        if ($rest -gt 0) { if ($bg) { Write-Host (' ' * $rest) -BackgroundColor $bg } else { Write-Host (' ' * $rest) } } else { Write-Host '' }
    }
    $sel = [int64](($items | Where-Object Checked | Measure-Object Size -Sum).Sum)
    $c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $enough = $c.FreeSpace -ge ([int64]($sel * 1.05) + 1GB)
    Line ''
    Line ('  Selected total: {0}' -f (Fmt $sel)) Yellow
    Line ('  Free on C: {0}   {1}' -f (Fmt $c.FreeSpace), $(if ($enough) { 'OK' } else { 'NOT ENOUGH SPACE' })) $(if ($enough) { 'Green' } else { 'Red' })
    Line ("  Restore users: " + (($map.GetEnumerator() | ForEach-Object { "$($_.Key)->$($_.Value)" }) -join ', ')) DarkGray
    for ($z = 0; $z -lt 4; $z++) { Line '' }

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $vk = $key.VirtualKeyCode
    if ($vk -eq 38 -and $cur -gt 0) { $cur-- }
    elseif ($vk -eq 40 -and $cur -lt $items.Count - 1) { $cur++ }
    elseif ($vk -eq 32) { $items[$cur].Checked = -not $items[$cur].Checked }
    elseif ($vk -eq 65) {
        $allOn = (@($items | Where-Object { -not $_.Checked }).Count -eq 0)
        foreach ($it in $items) { $it.Checked = -not $allOn }
    }
    elseif ($vk -eq 27) { [Console]::CursorVisible = $true; exit }
    elseif ($vk -eq 13) { break }
}

$chosen = @($items | Where-Object Checked)
Clear-Host
if (-not $chosen.Count) { Banner ''; Line '  Nothing selected.' Red; [Console]::CursorVisible = $true; Read-Host 'Press Enter to exit'; exit }
$need = [int64](($chosen | Measure-Object Size -Sum).Sum)

Banner 'Step 4/4  Ready'
Line ("  Data to restore : {0}  ({1} items)" -f (Fmt $need), $chosen.Count) White
Line ("  From            : {0}" -f $Source) White
Line '  Existing files are not overwritten.' DarkGray
Line ''
Line '  Press Enter to start...' Yellow
[void](Read-Host)

# ---------------- 5) Restore with live progress ----------------
Clear-Host
Banner 'Restoring...'
$topRow = [Console]::CursorTop + 1
$sw = [Diagnostics.Stopwatch]::StartNew()
$doneBase = [int64]0
$failed = @()
$log = Join-Path $env:TEMP "restore-log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
$script:lastFile = ''

function Draw([int64]$live, [string]$itemName, [int]$idx, [int]$cnt) {
    $done = [Math]::Min($need, $doneBase + $live)
    $frac = if ($need -gt 0) { $done / $need } else { 1 }
    $el = $sw.Elapsed.TotalSeconds
    $speed = if ($el -gt 1) { $done / $el } else { 0 }
    $eta = if ($speed -gt 0) { [TimeSpan]::FromSeconds(($need - $done) / $speed).ToString('hh\:mm\:ss') } else { '--:--:--' }
    [Console]::SetCursorPosition(0, $topRow)
    Line ("  Item {0}/{1}: {2}" -f $idx, $cnt, $itemName) Cyan
    Line ("  [{0}] {1,3}%" -f (Bar $frac 50), [int]($frac * 100)) Green
    Line ("  {0} / {1}" -f (Fmt $done), (Fmt $need)) White
    Line ("  Speed: {0}/s    Elapsed: {1}    ETA: {2}" -f (Fmt ([int64]$speed)), $sw.Elapsed.ToString('hh\:mm\:ss'), $eta) Yellow
    Line ''
    Line ("  " + $script:lastFile) DarkGray
}

$n = 0
foreach ($it in $chosen) {
    $n++
    Draw 0 $it.Name $n $chosen.Count
    switch ($it.Kind) {
        'folders' {
            $jn = 0
            foreach ($j in $it.Jobs) {
                $jn++
                New-Item -ItemType Directory -Path $j.Dst -Force | Out-Null
                $tmp = Join-Path $env:TEMP ("rs_{0}_{1}.log" -f $n, $jn)
                Remove-Item $tmp -Force
                $rcArgs = "`"$($j.Src)`" `"$($j.Dst)`" /E /XJ /XC /XN /XO /R:1 /W:1 /MT:16 /NP /NJH /NJS /NDL /BYTES /LOG:`"$tmp`""
                $p = Start-Process robocopy -ArgumentList $rcArgs -WindowStyle Hidden -PassThru
                $null = $p.Handle
                $reader = $null; $seen = [int64]0; $lastSz = [int64]0
                while (-not $p.HasExited) {
                    if (-not $reader -and (Test-Path $tmp)) {
                        $fs = [IO.File]::Open($tmp, 'Open', 'Read', 'ReadWrite')
                        $reader = New-Object IO.StreamReader($fs)
                    }
                    if ($reader) {
                        while (($ln = $reader.ReadLine()) -ne $null) {
                            if ($ln -match '\t\s*(\d+)\t(.+)$') {
                                $seen += [int64]$matches[1]; $lastSz = [int64]$matches[1]
                                $script:lastFile = [IO.Path]::GetFileName($matches[2].Trim())
                            }
                        }
                    }
                    $live = [Math]::Min($j.Size, [Math]::Max(0, $seen - $lastSz))
                    Draw $live $it.Name $n $chosen.Count
                    Start-Sleep -Milliseconds 250
                }
                if ($reader) { $reader.Close() }
                if ($p.ExitCode -ge 8) { $failed += $j.Src }
                if (Test-Path $tmp) { Get-Content $tmp | Add-Content $log; Remove-Item $tmp -Force }
                $doneBase += $j.Size
            }
        }
        'files' {
            foreach ($f in $it.Files) {
                New-Item -ItemType Directory -Path $f.Dst -Force | Out-Null
                $target = Join-Path $f.Dst (Split-Path $f.Src -Leaf)
                if (Test-Path $target) { Move-Item $target ($target + '.before-restore') -Force }
                Copy-Item $f.Src $f.Dst -Force
                $script:lastFile = Split-Path $f.Src -Leaf
            }
            $doneBase += $it.Size
        }
        'wifi' {
            foreach ($f in $it.Files) {
                netsh wlan add profile filename="$($f.Src)" user=all | Out-Null
                $script:lastFile = Split-Path $f.Src -Leaf
            }
            $doneBase += $it.Size
        }
    }
    Draw 0 $it.Name $n $chosen.Count
}
$sw.Stop()
$script:lastFile = ''
Draw 0 'Finished' $chosen.Count $chosen.Count

# ---------------- 6) Summary ----------------
[Console]::CursorVisible = $true
Write-Host ''
Line ('=' * $W) Green
Line '  RESTORE FINISHED' Green
Line ('=' * $W) Green
Line ("  Restored : {0}" -f (Fmt $need)) White
Line ("  Time     : {0}" -f $sw.Elapsed.ToString('hh\:mm\:ss')) White
Line ("  Extras   : {0}" -f $restoredRoot) White
Line '             (Outlook files, Sticky Notes, program list, custom folders are there)' DarkGray
Line ("  Log      : {0}" -f $log) DarkGray
if ($failed.Count) {
    Line '  Errors in these folders:' Red
    $failed | ForEach-Object { Line "    $_" Red }
} else {
    Line '  No errors.' Green
}
Write-Host ''
$ans = Read-Host '  Open the Restored-Backup folder? (Y/N)'
if ($ans -match '^[yY]') { Start-Process explorer.exe $restoredRoot }