# Undoes the DTS Mail parts of the Cloudflare setup: the Email Worker, the catch-all rule, the _dtsmail discovery
# record and the web app CNAME. Without -Yes it only lists what it would remove.
#
# Run it BEFORE deleting the Azure resource group (it reads the Cloudflare token from the server's settings).
# Mail for the domain stops arriving afterwards: point its MX records at another provider, or turn off Email Routing.
#
#   Remove-DtsCloudflare.ps1 [-ResourceGroup dtsmail] [-Domain example.com] [-WebHost mail.example.com] [-Yes]
param([string]$ResourceGroup, [string]$Domain, [string]$AccountId, [string]$WebHost, [switch]$Yes)
. (Join-Path $PSScriptRoot 'Common.ps1')

$ResourceGroup = Get-DtsResourceGroup $ResourceGroup
$state = Get-DtsState
$token = Get-DtsCloudflareToken $ResourceGroup
# Explicit parameters win over what setup saved.
$account = $AccountId
if (-not $account) { $account = $state['cloudflareAccountId'] }
if (-not $Domain) { $Domain = $state['domain'] }
if (-not $WebHost) { $WebHost = $state['webHost'] }
$domain = $Domain
$webHost = $WebHost
if (-not $account -or -not $domain) { throw 'Cloudflare account or domain unknown: pass -AccountId and -Domain (Find-DtsServer.ps1 shows the account ID).' }
$zone = Get-DtsZone $token $account $domain
if (-not $zone) { throw "Zone $domain not found." }

$plan = New-Object System.Collections.Generic.List[string]
$plan.Add("Delete Worker script dts-email-ingest (account $account)")
$plan.Add("Turn off the catch-all rule for $domain")
$records = @()
foreach ($n in @("_dtsmail.$domain", $webHost)) {
    if (-not $n) { continue }
    $found = Invoke-Cloudflare -Token $token -Path "/zones/$($zone.id)/dns_records?name=$([Uri]::EscapeDataString($n))"
    foreach ($r in @($found)) { if ($r) { $records += $r; $plan.Add("Delete DNS $($r.type) $($r.name) -> $($r.content)") } }
}

if (-not $Yes) {
    Write-Output 'Would do (run again with -Yes to apply):'
    $plan | ForEach-Object { Write-Output " - $_" }
    exit 0
}

try {
    $null = Invoke-Cloudflare -Token $token -Method 'PUT' -Path "/zones/$($zone.id)/email/routing/rules/catch_all" -Body @{
        enabled = $false; matchers = @(@{ type = 'all' }); actions = @(@{ type = 'drop' })
    }
    Write-Output "Catch-all rule turned off for $domain."
} catch { Write-Output "WARN: $($_.Exception.Message)" }
try {
    $null = Invoke-Cloudflare -Token $token -Method 'DELETE' -Path "/accounts/$account/workers/scripts/dts-email-ingest?force=true"
    Write-Output 'Worker dts-email-ingest deleted.'
} catch { Write-Output "WARN: $($_.Exception.Message)" }
foreach ($r in $records) {
    try { $null = Invoke-Cloudflare -Token $token -Method 'DELETE' -Path "/zones/$($zone.id)/dns_records/$($r.id)"; Write-Output "Deleted $($r.type) $($r.name)." }
    catch { Write-Output "WARN: $($_.Exception.Message)" }
}
Remove-DtsSecret 'cloudflare'
Write-Output 'OK: DTS Mail removed from Cloudflare. Email Routing itself and its MX records are still on; change them in the Cloudflare dashboard when you move your email.'
