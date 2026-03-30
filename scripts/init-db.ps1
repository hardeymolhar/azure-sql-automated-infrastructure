$ErrorActionPreference = 'Stop'

Write-Host "Starting DATA/LOG disk provisioning..."

# --- Configuration (explicit, no magic) ---
$diskDefinitions = @(
    @{
        Name        = 'NEWEST-LOG'
        MinSizeGB   = 500
        MaxSizeGB   = 530
        DriveLetter = 'I'
        Label       = 'LOG'
    },
    @{
        Name        = 'NEWEST-DATA'
        MinSizeGB   = 1000
        MaxSizeGB   = 1100
        DriveLetter = 'K'
        Label       = 'DATA'
    }
)

# --- Wait for disks to appear (VM boot safety) ---
$maxRetries = 20
$retryDelay = 15
$attempt    = 0

do {
    $rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }
    if ($rawDisks.Count -ge 2) { 
	        Write-Host "Managed disks are now visible to Windows. Proceeding with initialization."
	break }

    Write-Host "Waiting for managed disks to be visible..."
    Start-Sleep -Seconds $retryDelay
    $attempt++
} while ($attempt -lt $maxRetries)

if ($rawDisks.Count -lt 2) {
    throw "Expected managed disks not detected after waiting."
}

# --- Process each disk definition ---
foreach ($def in $diskDefinitions) {

    Write-Host "Processing $($def.Name) disk..."

    $disk = Get-Disk | Where-Object {
        $_.PartitionStyle -eq 'RAW' -and
        $_.Size -ge ($def.MinSizeGB * 1GB) -and
        $_.Size -le ($def.MaxSizeGB * 1GB)
    }

    if (-not $disk) {
        Write-Host "$($def.Name) disk already initialized or not found. Skipping."
        continue
    }

    if ($disk.Count -gt 1) {
        throw "Multiple disks matched size range for $($def.Name). Aborting."
    }

    $diskNumber = $disk.Number

    # STEP 1: Initialize
    Initialize-Disk -Number $diskNumber -PartitionStyle GPT -Confirm:$false

    # STEP 2: Bring online
    Set-Disk -Number $diskNumber -IsOffline $false

# STEP 3: Ensure partition with correct drive letter exists
$partition = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue |
             Where-Object { $_.DriveLetter -eq $def.DriveLetter }

if (-not $partition) {
    Write-Host "Creating partition with drive letter $($def.DriveLetter)..."
    $partition = New-Partition `
        -DiskNumber $diskNumber `
        -UseMaximumSize `
        -DriveLetter $def.DriveLetter
}


# STEP 4: Ensure volume is formatted
$volume = Get-Volume -DriveLetter $def.DriveLetter -ErrorAction SilentlyContinue

if (-not $volume -or -not $volume.FileSystem) {
    Write-Host "Formatting drive $($def.DriveLetter): as NTFS..."
    Format-Volume `
        -Partition $partition `
        -FileSystem NTFS `
        -NewFileSystemLabel $def.Label `
        -Confirm:$false
}

    Write-Host "$($def.Name) disk provisioned successfully."
}

Write-Host "DATA and LOG disk provisioning complete."
