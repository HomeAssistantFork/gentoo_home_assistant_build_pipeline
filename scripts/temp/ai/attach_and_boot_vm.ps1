$ErrorActionPreference = "Continue"
$vbm = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$vdi = "C:\Users\tamus\projects\linux\home_assistant_1\artifacts\gentooha-x64-debug-v2.vdi"
$vm = "GentooHA 1"

Write-Host "=== GentooHA VM Boot Script ==="

# Stop VM
Write-Host "Stopping VM..."
& $vbm controlvm $vm poweroff 2>&1 | Out-Null
Start-Sleep 3

# Check VDI exists
if (-not (Test-Path $vdi)) {
    Write-Host "VDI missing. Copying from WSL..."
    wsl -d Debian -u root -- cp /var/lib/ha-gentoo-hybrid/artifacts/gentooha-x64-debug.vdi "/mnt/c/Users/tamus/projects/linux/home_assistant_1/artifacts/gentooha-x64-debug-v2.vdi"
    Start-Sleep 5
}
$size = (Get-Item $vdi).Length / 1GB
Write-Host "VDI: $vdi ($([math]::Round($size,1)) GB)"

# Detach any current disk
Write-Host "Detaching current disk..."
& $vbm storageattach $vm --storagectl "SATA" --port 0 --device 0 --type hdd --medium none 2>&1 | Out-Null

# Close any stale registrations of this path
Write-Host "Closing stale medium registrations..."
& $vbm closemedium disk $vdi 2>&1 | Out-Null

# Attach fresh VDI
Write-Host "Attaching new VDI..."
& $vbm storageattach $vm --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdi 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Attach failed. Trying to register medium first..."
    & $vbm openmedium disk $vdi 2>&1
    & $vbm storageattach $vm --storagectl "SATA" --port 0 --device 0 --type hdd --medium $vdi 2>&1
}

# Ensure EFI off, correct boot order
& $vbm modifyvm $vm --firmware bios --boot1 disk --boot2 none --boot3 none 2>&1 | Out-Null

# Start VM
Write-Host "Starting VM headless..."
& $vbm startvm $vm --type headless 2>&1
Start-Sleep 60

# Screenshot
$shot = "C:\Users\tamus\projects\linux\home_assistant_1\artifacts\vm_v2_attach.png"
& $vbm controlvm $vm screenshotpng $shot 2>&1 | Out-Null
Write-Host "Screenshot: $shot (exists=$(Test-Path $shot))"

# Test ports
$ha = Test-NetConnection -ComputerName 127.0.0.1 -Port 8123 -InformationLevel Quiet -WarningAction SilentlyContinue
$ssh = Test-NetConnection -ComputerName 127.0.0.1 -Port 2222 -InformationLevel Quiet -WarningAction SilentlyContinue
Write-Host "HA:8123=$ha  SSH:2222=$ssh"
