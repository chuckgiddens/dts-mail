# Gives the web app its own address (e.g. mail.example.com): a DNS-only CNAME in Cloudflare to the Static Web App,
# then the custom domain on the Static Web App, which validates it and issues a free certificate.
#
#   Set-WebDomain.ps1 -HostName mail.example.com [-ResourceGroup dtsmail] [-Minutes 15]
param(
    [Parameter(Mandatory = $true)][string]$HostName,
    [string]$ResourceGroup,
    [int]$Minutes = 15
)
. (Join-Path $PSScriptRoot 'Common.ps1')

$HostName = $HostName.Trim().ToLowerInvariant()
$ResourceGroup = Get-DtsResourceGroup $ResourceGroup
$state = Get-DtsState
$swa = $state['staticWebAppName']
if (-not $swa) { throw 'Unknown Static Web App. Run Deploy-Infra.ps1 first.' }
$target = Invoke-Az staticwebapp show -n $swa -g $ResourceGroup --query defaultHostname -o tsv -Raw

$token = Get-DtsCloudflareToken $ResourceGroup
$account = $state['cloudflareAccountId']
$domain = $state['domain']
if (-not $account -or -not $domain) { throw 'Cloudflare account or domain unknown. Run Set-CloudflareToken.ps1 first.' }
if (-not $HostName.EndsWith(".$domain") -and $HostName -ne $domain) { throw "$HostName is not under $domain." }
$zone = Get-DtsZone $token $account $domain
if (-not $zone) { throw "Zone $domain not found in Cloudflare." }

# DNS only (grey cloud): Static Web Apps validates the CNAME and serves its own certificate.
$null = Set-DtsDnsRecord -Token $token -ZoneId $zone.id -Type 'CNAME' -Name $HostName -Content $target -Proxied $false
Write-Output "DNS: $HostName -> $target (DNS only)."

$existing = $null
try { $existing = Invoke-Az staticwebapp hostname show -n $swa -g $ResourceGroup --hostname $HostName -o json } catch { }
if (-not $existing) {
    Write-Output 'Adding the custom domain to the Static Web App (validation can take several minutes)...'
    $null = Invoke-Az staticwebapp hostname set -n $swa -g $ResourceGroup --hostname $HostName --no-wait -o json
}

$deadline = (Get-Date).AddMinutes($Minutes)
$status = ''
while ((Get-Date) -lt $deadline) {
    try { $status = Invoke-Az staticwebapp hostname show -n $swa -g $ResourceGroup --hostname $HostName --query status -o tsv -Raw } catch { $status = 'Pending' }
    if ($status -eq 'Ready') { break }
    if ($status -eq 'Failed') { break }
    Start-Sleep -Seconds 20
}
if ($status -eq 'Ready') {
    Set-DtsState @{ webHost = $HostName; webDomainReady = $true }
    Write-Output "OK: https://$HostName is ready."
} else {
    Write-Output "WAIT: the custom domain is '$status' after $Minutes minutes. Run this again later; Azure keeps validating in the background."
    exit 2
}
