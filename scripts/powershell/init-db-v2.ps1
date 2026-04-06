Start-Transcript -Path "C:\Windows\Temp\disk-provisioning.log" -Append

# -------------------------
# Step 0 — Design intent
# -------------------------
$roleBySize = @{
    1024 = @{
        Role        = 'DATA'
        DriveLetters= @('I','K','M','P')
        LabelPrefix = 'DATA'
    }
    512 = @{
        Role        = 'LOG'
        DriveLetters= @('F','L','N','O')
        LabelPrefix = 'LOG'
    }
}

# ---------------------------
# Step 1 — Discover RAW disks
# ---------------------------
$rawDisks = Get-Disk |
    Where-Object PartitionStyle -eq 'RAW' |
    Select-Object *,
        @{ Name = 'SizeGB'; Expression = { [math]::Round($_.Size / 1GB) } }

# -------------------------
# Step 2 — Build execution plan
# -------------------------
$executionPlan = @()

foreach ($size in $roleBySize.Keys) {

    $roleDef = $roleBySize[$size]

    $roleDisks = $rawDisks |
        Where-Object SizeGB -eq $size |
        Sort-Object Number

    for ($i = 0; $i -lt $roleDisks.Count; $i++) {

        if ($i -ge $roleDef.DriveLetters.Count) {
            Write-Warning "Extra $($roleDef.Role) disk detected. Skipping."
            continue
        }

        $executionPlan += [PSCustomObject]@{
            DiskNumber  = $roleDisks[$i].Number
            SizeGB      = $size
            Role        = $roleDef.Role
            DriveLetter = $roleDef.DriveLetters[$i]
            Label       = "$($roleDef.LabelPrefix)$($i+1)"
        }
    }
}

# ------------------------------
# Step 3 — Capture used letters
# ------------------------------
$usedLetters = Get-Volume |
    Where-Object DriveLetter |
    Select-Object -ExpandProperty DriveLetter

# -------------------------
# Step 4 — Execute safely
# -------------------------
foreach ($d in $executionPlan) {

    $disk = Get-Disk -Number $d.DiskNumber

    if ($disk.PartitionStyle -ne 'RAW') {
        Write-Warning "Disk $($d.DiskNumber) already initialized. Skipping."
        continue
    }

    if ($usedLetters -contains $d.DriveLetter) {
        Write-Warning "Drive letter $($d.DriveLetter) in use. Skipping disk $($d.DiskNumber)."
        continue
    }

    Initialize-Disk -Number $d.DiskNumber -PartitionStyle GPT -PassThru |
        New-Partition -UseMaximumSize -DriveLetter $d.DriveLetter |
        Format-Volume -FileSystem NTFS `
                      -NewFileSystemLabel $d.Label `
                      -AllocationUnitSize 65536 `
                      -Confirm:$false

    $usedLetters += $d.DriveLetter
}

Stop-Transcript
