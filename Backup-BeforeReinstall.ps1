# Backup-BeforeReinstall.ps1  (works on Windows 7 / PowerShell 2.0 and newer)
# Keys: Up/Down = move | Space = tick | A = all/none | C = add custom folder | Enter = continue | Esc = quit
# Optional: -Dest "E:\" to force the destination drive

param([string]$Dest = "")

# --- self-elevate to Administrator ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = $MyInvocation.MyCommand.Path
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$self`""
    if ($Dest) { $a += " -Dest `"$Dest`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $a
    exit
}

$ErrorActionPreference = 'SilentlyContinue'

# --- bigger console window (old Win7 console is only 80x25) ---
try {
    $raw = $Host.UI.RawUI
    $b = $raw.BufferSize
    $raw.BufferSize = New-Object Management.Automation.Host.Size(110, [Math]::Max($b.Height, 500))
    $raw.WindowSize = New-Object Management.Automation.Host.Size(110, 40)
} catch {}
$Host.UI.RawUI.WindowTitle = 'Backup before Windows reinstall'

$stamp  = Get-Date -Format 'yyyyMMdd_HHmm'
$pcName = $env:COMPUTERNAME
$skip   = 'Public','Default','Default User','All Users','defaultuser0'
$users  = @(Get-ChildItem 'C:\Users' -Force | Where-Object { $_.PSIsContainer -and ($skip -notcontains $_.Name) })
$W      = [Math]::Max(70, $Host.UI.RawUI.WindowSize.Width - 1)
$FULL   = '#'
$EMPTY  = '.'

# ---------------- helpers ----------------
function Fmt([int64]$b) {
    if ($b -ge 1GB) { '{0:N2} GB' -f ($b/1GB) }
    elseif ($b -ge 1MB) { '{0:N1} MB' -f ($b/1MB) }
    else { '{0:N0} KB' -f ($b/1KB) }
}
function TS([double]$sec) {
    if ($sec -lt 0) { $sec = 0 }
    if ($sec -gt 356400) { $sec = 356400 }
    $h = [int][Math]::Floor($sec / 3600)
    $m = [int][Math]::Floor(($sec % 3600) / 60)
    $s = [int][Math]::Floor($sec % 60)
    '{0:00}:{1:00}:{2:00}' -f $h, $m, $s
}
function Line([string]$t = '', $fg = 'Gray') {
    if ($t.Length -gt $W) { $t = $t.Substring(0, $W) } else { $t = $t.PadRight($W) }
    Write-Host $t -ForegroundColor $fg
}
function Bar([double]$frac, [int]$len = 40) {
    if ($frac -gt 1) { $frac = 1 }; if ($frac -lt 0) { $frac = 0 }
    $f = [int][Math]::Floor($frac * $len)
    ($FULL * $f) + ($EMPTY * ($len - $f))
}
function Banner([string]$sub) {
    Line ('=' * $W) Cyan
    Line "  WINDOWS REINSTALL BACKUP    PC: $pcName    $(Get-Date -Format 'yyyy-MM-dd HH:mm')" White
    if ($sub) { Line "  $sub" DarkCyan }
    Line ('=' * $W) Cyan
}
function DirSize($p) {
    [int64](Get-ChildItem $p -Recurse -Force |
        Where-Object { (-not $_.PSIsContainer) -and (-not ($_.Attributes -band [IO.FileAttributes]::Offline)) } |
        Measure-Object Length -Sum).Sum
}
function NewItem($name, $kind, $checked) {
    New-Object PSObject -Property @{
        Name = $name; Kind = $kind; Checked = $checked; Size = [int64]0
        Jobs = (New-Object System.Collections.ArrayList)
        Files = (New-Object System.Collections.ArrayList)
    }
}
function AddJob($it, $src, $rel) {
    [void]$it.Jobs.Add((New-Object PSObject -Property @{ Src = $src; Rel = $rel; Size = [int64]0 }))
}
# ---------------- 1) Find folders ----------------
[Console]::CursorVisible = $false
Clear-Host
Banner 'Step 1/3  Scanning'
$items = New-Object System.Collections.ArrayList

foreach ($f in 'Desktop', 'Downloads', 'Documents', 'Pictures', 'Videos', 'Music') {
    $it = NewItem $f 'folders' ($f -ne 'Music')
    foreach ($u in $users) {
        $p = Join-Path $u.FullName $f
        if (Test-Path $p) { AddJob $it $p "Users\$($u.Name)\$f" }
        foreach ($od in @(Get-ChildItem $u.FullName -Force | Where-Object { $_.PSIsContainer -and $_.Name -like 'OneDrive*' })) {
            $p2 = Join-Path $od.FullName $f
            if (Test-Path $p2) { AddJob $it $p2 "Users\$($u.Name)\$($od.Name)\$f" }
        }
    }
    if ($it.Jobs.Count -gt 0) { [void]$items.Add($it) }
}

$bm = NewItem 'Browser bookmarks (Chrome / Edge / Brave / Firefox)' 'files' $true
$browsers = @{
    Chrome = 'AppData\Local\Google\Chrome\User Data'
    Edge   = 'AppData\Local\Microsoft\Edge\User Data'
    Brave  = 'AppData\Local\BraveSoftware\Brave-Browser\User Data'
}
foreach ($u in $users) {
    foreach ($b in $browsers.GetEnumerator()) {
        $ud = Join-Path $u.FullName $b.Value
        if (-not (Test-Path $ud)) { continue }
        foreach ($pd in @(Get-ChildItem $ud | Where-Object { $_.PSIsContainer -and ($_.Name -eq 'Default' -or $_.Name -like 'Profile *') })) {
            $file = Join-Path $pd.FullName 'Bookmarks'
            if (Test-Path $file) { [void]$bm.Files.Add((New-Object PSObject -Property @{ Src = $file; Rel = "Browsers\$($u.Name)\$($b.Key)_$($pd.Name)" })) }
        }
    }
    $ff = Join-Path $u.FullName 'AppData\Roaming\Mozilla\Firefox\Profiles'
    if (Test-Path $ff) {
        foreach ($pd in @(Get-ChildItem $ff | Where-Object { $_.PSIsContainer })) {
            foreach ($n in 'places.sqlite', 'logins.json', 'key4.db', 'key3.db') {
                $file = Join-Path $pd.FullName $n
                if (Test-Path $file) { [void]$bm.Files.Add((New-Object PSObject -Property @{ Src = $file; Rel = "Browsers\$($u.Name)\Firefox_$($pd.Name)" })) }
            }
        }
    }
}
foreach ($f in $bm.Files) { $bm.Size += (Get-Item $f.Src).Length }
if ($bm.Files.Count -gt 0) { [void]$items.Add($bm) }

$ol = NewItem 'Outlook data (PST/OST)' 'folders' $true
$sn = NewItem 'Sticky Notes' 'folders' $true
foreach ($u in $users) {
    $p = Join-Path $u.FullName 'AppData\Local\Microsoft\Outlook'
    if (Test-Path $p) { AddJob $ol $p "Users\$($u.Name)\OutlookData" }
    # Windows 10 Sticky Notes
    $p = Join-Path $u.FullName 'AppData\Local\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState'
    if (Test-Path $p) { AddJob $sn $p "Users\$($u.Name)\StickyNotes" }
    # Windows 7 Sticky Notes
    $p = Join-Path $u.FullName 'AppData\Roaming\Microsoft\Sticky Notes'
    if (Test-Path $p) { AddJob $sn $p "Users\$($u.Name)\StickyNotes" }
}
foreach ($it in @($ol, $sn)) { if ($it.Jobs.Count -gt 0) { [void]$items.Add($it) } }

[void]$items.Add((NewItem 'System info (Wi-Fi passwords, programs, printers)' 'sysinfo' $true))

# ---------------- 1b) Measure sizes with progress ----------------
$allJobs = New-Object System.Collections.ArrayList
foreach ($it in $items) { foreach ($j in $it.Jobs) { [void]$allJobs.Add((New-Object PSObject -Property @{ Item = $it; Job = $j })) } }
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

# ---------------- 2) Checkbox menu ----------------
$cur = 0
$nameW = $W - 20
Clear-Host
while ($true) {
    [Console]::SetCursorPosition(0, 0)
    Banner 'Step 2/3  Choose what to back up'
    Line '  Up/Down: move   Space: tick   A: all/none   C: add folder   Enter: continue   Esc: quit' DarkGray
    Line ''
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $bg = $null; if ($i -eq $cur) { $bg = 'DarkGray' }
        $name = $it.Name; if ($name.Length -gt $nameW) { $name = $name.Substring(0, $nameW - 3) + '...' }
        $sizeColor = 'Gray'; if ($it.Size -ge 20GB) { $sizeColor = 'Red' } elseif ($it.Size -ge 5GB) { $sizeColor = 'Yellow' }
        $pre = '  '; if ($i -eq $cur) { $pre = '> ' }
        $args1 = @{ NoNewline = $true }; if ($bg) { $args1.BackgroundColor = $bg }
        Write-Host $pre @args1
        if ($it.Checked) { Write-Host '[x]' -ForegroundColor Green @args1 } else { Write-Host '[ ]' -ForegroundColor DarkGray @args1 }
        Write-Host (' ' + $name.PadRight($nameW)) -ForegroundColor White @args1
        Write-Host ((Fmt $it.Size).PadLeft(11)) -ForegroundColor $sizeColor @args1
        $rest = $W - (2 + 3 + 1 + $nameW + 11)
        if ($rest -gt 0) { if ($bg) { Write-Host (' ' * $rest) -BackgroundColor $bg } else { Write-Host (' ' * $rest) } } else { Write-Host '' }
    }
    $sel = [int64](($items | Where-Object { $_.Checked } | Measure-Object Size -Sum).Sum)
    Line ''
    Line ('  Selected total: {0}' -f (Fmt $sel)) Yellow
    Line ''
    Line '  Drives:' White
    $drv = @(Get-WmiObject Win32_LogicalDisk | Where-Object { ($_.DriveType -eq 2 -or $_.DriveType -eq 3) -and $_.Size -gt 0 })
    $lines = 0
    foreach ($d in $drv) {
        $usedFrac = 1 - ([double]$d.FreeSpace / [double]$d.Size)
        $enough = ($d.DeviceID -ne 'C:') -and ($d.FreeSpace -ge ([int64]($sel * 1.1) + 1GB))
        if ($d.DeviceID -eq 'C:') { $col = 'DarkGray'; $tag = 'source' }
        elseif ($enough) { $col = 'Green'; $tag = 'OK' }
        else { $col = 'Red'; $tag = 'not enough space' }
        Line ('    {0}  [{1}]  {2} free of {3}   {4}' -f $d.DeviceID, (Bar $usedFrac 20), (Fmt $d.FreeSpace), (Fmt $d.Size), $tag) $col
        $lines++
    }
    for ($z = $lines; $z -lt 6; $z++) { Line '' }

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $vk = $key.VirtualKeyCode
    if ($vk -eq 38 -and $cur -gt 0) { $cur-- }
    elseif ($vk -eq 40 -and $cur -lt $items.Count - 1) { $cur++ }
    elseif ($vk -eq 32) { $items[$cur].Checked = -not $items[$cur].Checked }
    elseif ($vk -eq 65) {
        $allOn = (@($items | Where-Object { -not $_.Checked }).Count -eq 0)
        foreach ($it in $items) { $it.Checked = -not $allOn }
    }
    elseif ($vk -eq 67) {
        [Console]::CursorVisible = $true
        Write-Host ''
        $p = (Read-Host '  Full path of folder to add').Trim('"').TrimEnd('\')
        [Console]::CursorVisible = $false
        if ($p -and (Test-Path $p -PathType Container)) {
            $it = NewItem "Custom: $p" 'folders' $true
            $leaf = ($p -replace '[:\\\/]+', '_').Trim('_')
            AddJob $it $p "Custom\$leaf"
            Write-Host '  Calculating size...' -ForegroundColor Yellow
            $it.Jobs[0].Size = DirSize $p
            $it.Size = $it.Jobs[0].Size
            $items.Insert($items.Count - 1, $it)
        }
        Clear-Host
    }
    elseif ($vk -eq 27) { [Console]::CursorVisible = $true; exit }
    elseif ($vk -eq 13) { break }
}

$chosen = @($items | Where-Object { $_.Checked })
Clear-Host
if ($chosen.Count -eq 0) { Banner ''; Line '  Nothing selected.' Red; [Console]::CursorVisible = $true; Read-Host 'Press Enter to exit'; exit }
$need = [int64](($chosen | Measure-Object Size -Sum).Sum)

# ---------------- 3) Destination ----------------
$required = [int64]($need * 1.1) + 1GB
if (-not $Dest) {
    $disks = @(Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DeviceID -ne 'C:' -and ($_.DriveType -eq 2 -or $_.DriveType -eq 3) -and $_.FreeSpace -gt 0 })
    $best = $disks | Where-Object { $_.FreeSpace -ge $required } | Sort-Object FreeSpace -Descending | Select-Object -First 1
    if (-not $best) {
        Banner ''
        Line "  No drive (other than C:) has enough free space. Need about $(Fmt $required)." Red
        [Console]::CursorVisible = $true; Read-Host 'Press Enter to exit'; exit 1
    }
    $Dest = $best.DeviceID + '\'
}
$root = Join-Path $Dest "Backup_${pcName}_$stamp"
New-Item -ItemType Directory -Path $root -Force | Out-Null
$log = Join-Path $root 'backup-log.txt'

Banner 'Step 3/3  Ready'
Line ("  Data to copy : {0}  ({1} items)" -f (Fmt $need), $chosen.Count) White
Line ("  Destination  : {0}" -f $root) White
Line ''
Line '  Press Enter to start...' Yellow
[void](Read-Host)

# ---------------- 4) Backup with live progress ----------------
Clear-Host
Banner 'Backing up...'
$topRow = [Console]::CursorTop + 1
$sw = [Diagnostics.Stopwatch]::StartNew()
$doneBase = [int64]0
$failed = New-Object System.Collections.ArrayList
$script:lastFile = ''

function Draw([int64]$live, [string]$itemName, [int]$idx, [int]$cnt) {
    $done = [Math]::Min($need, $doneBase + $live)
    if ($need -gt 0) { $frac = $done / $need } else { $frac = 1 }
    $el = $sw.Elapsed.TotalSeconds
    $speed = 0; if ($el -gt 1) { $speed = $done / $el }
    $eta = '--:--:--'; if ($speed -gt 0) { $eta = TS (($need - $done) / $speed) }
    [Console]::SetCursorPosition(0, $topRow)
    Line ("  Item {0}/{1}: {2}" -f $idx, $cnt, $itemName) Cyan
    Line ("  [{0}] {1,3}%" -f (Bar $frac 50), [int]($frac * 100)) Green
    Line ("  {0} / {1}" -f (Fmt $done), (Fmt $need)) White
    Line ("  Speed: {0}/s    Elapsed: {1}    ETA: {2}" -f (Fmt ([int64]$speed)), (TS $el), $eta) Yellow
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
                $dst = Join-Path $root $j.Rel
                $tmp = Join-Path $env:TEMP ("rc_{0}_{1}.log" -f $n, $jn)
                Remove-Item $tmp -Force
                $rcArgs = "`"$($j.Src)`" `"$dst`" /E /XJ /XA:O /R:1 /W:1 /MT:16 /NP /NJH /NJS /NDL /BYTES /XF desktop.ini Thumbs.db /LOG:`"$tmp`""
                $p = Start-Process robocopy -ArgumentList $rcArgs -WindowStyle Hidden -PassThru
                $null = $p.Handle
                $reader = $null; $seen = [int64]0; $lastSz = [int64]0
                while (-not $p.HasExited) {
                    if ((-not $reader) -and (Test-Path $tmp)) {
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
                if ($p.ExitCode -ge 8) { [void]$failed.Add($j.Src) }
                if (Test-Path $tmp) { Get-Content $tmp | Add-Content $log; Remove-Item $tmp -Force }
                $doneBase += $j.Size
            }
        }
        'files' {
            foreach ($f in $it.Files) {
                $d = Join-Path $root $f.Rel
                New-Item -ItemType Directory -Path $d -Force | Out-Null
                Copy-Item $f.Src $d -Force
            }
            $doneBase += $it.Size
        }
        'sysinfo' {
            $info = Join-Path $root 'SystemInfo'
            New-Item -ItemType Directory -Path $info -Force | Out-Null
            netsh wlan export profile key=clear folder="$info" | Out-Null
            Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
                Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion, Publisher | Sort-Object DisplayName |
                Export-Csv (Join-Path $info 'installed-programs.csv') -NoTypeInformation
            Get-WmiObject Win32_Printer | Select-Object Name, DriverName, PortName | Export-Csv (Join-Path $info 'printers.csv') -NoTypeInformation
            ipconfig /all | Out-File (Join-Path $info 'ipconfig.txt')
            net use | Out-File (Join-Path $info 'network-drives.txt')
        }
    }
    Draw 0 $it.Name $n $chosen.Count
}
$sw.Stop()
$script:lastFile = ''
Draw 0 'Finished' $chosen.Count $chosen.Count

# ---------------- 5) Summary ----------------
[Console]::CursorVisible = $true
Write-Host ''
Line ('=' * $W) Green
Line '  BACKUP FINISHED' Green
Line ('=' * $W) Green
Line ("  Copied      : {0}" -f (Fmt $need)) White
Line ("  Time        : {0}" -f (TS $sw.Elapsed.TotalSeconds)) White
Line ("  Backup path : {0}" -f $root) White
if ($failed.Count -gt 0) {
    Line '  Errors in these folders (see backup-log.txt):' Red
    foreach ($f in $failed) { Line "    $f" Red }
} else {
    Line '  No errors.' Green
}
Write-Host ''
$ans = Read-Host '  Open the backup folder? (Y/N)'
if ($ans -match '^[yY]') { Start-Process explorer.exe $root }