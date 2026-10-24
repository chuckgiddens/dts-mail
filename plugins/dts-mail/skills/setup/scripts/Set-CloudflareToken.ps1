# Asks for the Cloudflare API token in a masked window, checks it can reach everything DTS Mail needs, and keeps it
# (encrypted for this Windows user) until Deploy-Infra.ps1 hands it to the server. Prints only check results.
#
#   Set-CloudflareToken.ps1 -AccountId <id> -Domain example.com            # ask for a new token
#   Set-CloudflareToken.ps1 -AccountId <id> -Domain example.com -UseSaved  # re-check the token already saved
param(
    [Parameter(Mandatory = $true)][string]$AccountId,
    [Parameter(Mandatory = $true)][string]$Domain,
    [switch]$UseSaved,
    [string]$ResourceGroup
)
. (Join-Path $PSScriptRoot 'Common.ps1')

$AccountId = $AccountId.Trim()
$Domain = $Domain.Trim().ToLowerInvariant()

if ($UseSaved) {
    # A token that failed a permission check earlier (and was then edited in Cloudflare), else the accepted one.
    $token = Get-DtsSecret 'cloudflare-pending'
    if (-not $token) {
        $rg = $null
        if ($ResourceGroup) { $rg = $ResourceGroup } else { $rg = (Get-DtsState)['resourceGroup'] }
        $token = Get-DtsCloudflareToken $rg
    }
} else {
    $token = & (Join-Path $PSScriptRoot 'Read-Secret.ps1') -Title 'DTS Mail - Cloudflare' `
        -Prompt 'Paste the Cloudflare API token you just created, then press OK. It is not shown to Claude.'
}

$results = New-Object System.Collections.Generic.List[object]
# -WarnOnly: Cloudflare doesn't document which permission each Email Sending call needs, so a failure there is
# reported but doesn't stop setup (outbound mail is what would be affected).
function Test-Step([string]$Name, [string]$Permission, [scriptblock]$Check, [switch]$WarnOnly) {
    try { $detail = & $Check; $results.Add([pscustomobject]@{ Check = $Name; Result = 'OK'; Detail = "$detail" }) }
    catch {
        $level = 'FAIL'
        if ($WarnOnly) { $level = 'WARN' }
        $results.Add([pscustomobject]@{ Check = $Name; Result = $level; Detail = "Needs '$Permission'. $($_.Exception.Message)" })
    }
}

# The token itself (account-owned tokens verify under the account; user tokens under /user).
$verified = $false
try { $v = Invoke-Cloudflare -Token $token -Path "/accounts/$AccountId/tokens/verify"; $verified = ($v.status -eq 'active') } catch { }
if (-not $verified) {
    try { $v = Invoke-Cloudflare -Token $token -Path '/user/tokens/verify'; $verified = ($v.status -eq 'active') } catch { }
}
if (-not $verified) {
    Write-Output 'FAIL: Cloudflare did not accept this token (wrong value, expired, or created for another account). Nothing was saved.'
    exit 1
}

$zone = $null
Test-Step 'Zone found and active' 'Zone: Read' {
    $script:zone = Get-DtsZone $token $AccountId $Domain
    if (-not $script:zone) { throw "No zone named $Domain in account $AccountId (or the token can't see it)." }
    if ($script:zone.status -ne 'active') { throw "Zone status is '$($script:zone.status)': finish adding the domain to Cloudflare first." }
    "zone $($script:zone.id)"
}
$zone = $script:zone

if ($zone) {
    $zid = $zone.id
    Test-Step 'DNS records' 'DNS: Edit' { $null = Invoke-Cloudflare -Token $token -Path "/zones/$zid/dns_records?per_page=1"; 'readable' }
    Test-Step 'Email Routing settings' 'Zone Settings: Edit' { $r = Invoke-Cloudflare -Token $token -Path "/zones/$zid/email/routing"; "enabled=$($r.enabled)" }
    Test-Step 'Email Routing rules' 'Email Routing Rules: Edit' { $null = Invoke-Cloudflare -Token $token -Path "/zones/$zid/email/routing/rules/catch_all"; 'readable' }
    Test-Step 'Email Sending' 'Email Sending: Edit' { $null = Invoke-Cloudflare -Token $token -Path "/zones/$zid/email/sending/subdomains"; 'readable' } -WarnOnly
}
Test-Step 'Email Routing addresses' 'Email Routing Addresses: Edit' { $null = Invoke-Cloudflare -Token $token -Path "/accounts/$AccountId/email/routing/addresses?per_page=5"; 'readable' }
Test-Step 'Workers scripts' 'Workers Scripts: Edit' { $null = Invoke-Cloudflare -Token $token -Path "/accounts/$AccountId/workers/scripts"; 'readable' }

$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
if ($failed -gt 0) {
    # Kept aside (encrypted) so the user can fix the permissions in Cloudflare and re-check with -UseSaved.
    Save-DtsSecret 'cloudflare-pending' $token
    Write-Output "FAIL: $failed check(s) failed. Edit the token's permissions in Cloudflare (see references/cloudflare-token.md), then run this again with -UseSaved. The token is not in use yet."
    exit 1
}

if (@($results | Where-Object { $_.Result -eq 'WARN' }).Count -gt 0) {
    Write-Output 'WARN: the Email Sending check failed. Receiving will work; sending to the outside world needs the Email Sending: Edit permission and the Workers Paid plan.'
}
Save-DtsSecret 'cloudflare' $token
Remove-DtsSecret 'cloudflare-pending'
Set-DtsState @{ cloudflareAccountId = $AccountId; domain = $Domain; cloudflareZoneId = $zone.id }
Write-Output 'OK: token accepted and saved for this setup (encrypted for your Windows user). These checks confirm access; write access is confirmed as setup runs.'
