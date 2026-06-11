# setup_windows.ps1 — One-time Windows PC setup for CereLink data sharing.
# Run in PowerShell as Administrator on the Central PC.
#
# This script:
#   1. Configures a static IP on the second NIC (the one connected to the switch)
#   2. Sets the adapter's network profile to Private (required for SMB to work)
#   3. Opens firewall port 445 for SMB
#   4. Creates C:\blackrock and shares it
#   5. Sets a password on the Windows user account so the Mac can authenticate
#
# Usage:
#   Right-click PowerShell → "Run as Administrator"
#   cd to the repo directory, then:
#   .\setup_windows.ps1

$ErrorActionPreference = "Stop"

function Header($msg) { Write-Host ""; Write-Host "▶ $msg" -ForegroundColor Cyan }
function OK($msg)     { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg)   { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Info($msg)   { Write-Host "  $msg" }

# ── Config — edit these if your setup differs ─────────────────────────────────
$SHARE_ADAPTER_IP   = "192.168.50.1"       # IP to assign to the switch-facing NIC
$SHARE_ADAPTER_MASK = 24                   # /24 = 255.255.255.0
$BLACKROCK_DIR      = "C:\blackrock"       # Central save path; must match Central config
$SHARE_NAME         = "blackrock"          # SMB share name (Mac mounts as smb://IP/blackrock)
$WIN_USERNAME       = $env:USERNAME        # Current Windows username
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "=============================="
Write-Host " CereLink Windows Setup"
Write-Host "=============================="

# ── 1. Find the correct network adapter ──────────────────────────────────────
Header "Network adapters"
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
Info "Active adapters:"
$adapters | ForEach-Object { Info "  $($_.Name) — $($_.InterfaceDescription)" }

# Find the adapter that doesn't already have an NSP-range IP
$shareAdapter = $null
foreach ($a in $adapters) {
    $ips = (Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    $isNSP = $ips | Where-Object { $_ -match "^192\.168\.137\." }
    if (-not $isNSP) {
        $shareAdapter = $a
        break
    }
}

if (-not $shareAdapter) {
    Warn "Could not auto-detect the switch-facing NIC. Listing all adapters:"
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status
    $adapterName = Read-Host "Enter the adapter Name to use for file sharing"
    $shareAdapter = Get-NetAdapter -Name $adapterName
}
OK "Using adapter: $($shareAdapter.Name)"

# ── 2. Assign static IP ───────────────────────────────────────────────────────
Header "Setting static IP $SHARE_ADAPTER_IP on '$($shareAdapter.Name)'"
$existing = Get-NetIPAddress -InterfaceIndex $shareAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
if ($existing | Where-Object { $_.IPAddress -eq $SHARE_ADAPTER_IP }) {
    OK "IP $SHARE_ADAPTER_IP already assigned"
} else {
    # Remove any existing IPv4 addresses first to avoid conflicts
    $existing | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $shareAdapter.Name -IPAddress $SHARE_ADAPTER_IP `
        -PrefixLength $SHARE_ADAPTER_MASK | Out-Null
    OK "Assigned $SHARE_ADAPTER_IP/$SHARE_ADAPTER_MASK"
}

# ── 3. Set network profile to Private ────────────────────────────────────────
# Windows blocks SMB on "Public" network profiles regardless of firewall rules.
Header "Setting network profile to Private"
Set-NetConnectionProfile -InterfaceAlias $shareAdapter.Name -NetworkCategory Private
OK "Network profile set to Private"

# ── 4. Firewall rule for SMB (port 445) ───────────────────────────────────────
Header "Configuring firewall"
$ruleName = "CereLink SMB Inbound"
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    OK "Firewall rule '$ruleName' already exists"
} else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 445 `
        -Action Allow `
        -Profile Any | Out-Null
    OK "Firewall rule '$ruleName' created"
}

# ── 5. Create and share the blackrock folder ──────────────────────────────────
Header "Creating and sharing $BLACKROCK_DIR"
if (-not (Test-Path $BLACKROCK_DIR)) {
    New-Item -ItemType Directory -Path $BLACKROCK_DIR | Out-Null
    OK "Created $BLACKROCK_DIR"
} else {
    OK "$BLACKROCK_DIR already exists"
}

# Check if already shared
$existingShare = Get-SmbShare -Name $SHARE_NAME -ErrorAction SilentlyContinue
if ($existingShare) {
    OK "Share '$SHARE_NAME' already exists"
} else {
    New-SmbShare -Name $SHARE_NAME -Path $BLACKROCK_DIR -FullAccess "Everyone" | Out-Null
    OK "Shared as \\$(hostname)\$SHARE_NAME"
}

# ── 6. Windows account password ───────────────────────────────────────────────
# macOS Finder requires a username + password; Windows accounts with no password
# are rejected. Set a password here so the Mac can authenticate.
Header "Windows user account"
Info "Current user: $WIN_USERNAME"
Info ""
Info "If your account has no password, the Mac cannot authenticate to the SMB share."
Info "To set a password, run the following in an Admin Command Prompt:"
Info ""
Info "    net user $WIN_USERNAME YourPasswordHere"
Info ""
Info "Then connect from the Mac with: smb://$SHARE_ADAPTER_IP/$SHARE_NAME"
Info "Credentials: username=$WIN_USERNAME, password=<what you set above>"
Info ""
Info "(Mac stores the password in Keychain after first login — you won't be asked again.)"

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================="
Write-Host " Setup complete!" -ForegroundColor Green
Write-Host "=============================="
Write-Host ""
Write-Host "In Blackrock Central:"
Write-Host "  File → Preferences → Save → set save path to $BLACKROCK_DIR"
Write-Host ""
Write-Host "From the Mac, connect to the share:"
Write-Host "  Finder → Go → Connect to Server → smb://$SHARE_ADAPTER_IP/$SHARE_NAME"
Write-Host "  Or via Terminal: open smb://$SHARE_ADAPTER_IP/$SHARE_NAME"
