# Finds the DTS Mail server(s) in the signed-in Azure subscription (resources tagged app=dts-mail) and remembers the
# one to manage, so the other scripts work from any PC, not only the one setup ran on. Prints no secrets.
#
#   Find-DtsServer.ps1 [-ResourceGroup dtsmail]
param([string]$ResourceGroup)
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not $ResourceGroup) {
    $groups = @(Invoke-Az group list --query "[?tags.app=='dts-mail'].name" -o json)
    if ($groups.Count -eq 0 -or -not $groups[0]) {
        $apps = @(Invoke-Az functionapp list --query "[?tags.app=='dts-mail'].resourceGroup" -o json)
        $groups = @($apps | Where-Object { $_ } | Select-Object -Unique)
    }
    if ($groups.Count -eq 0 -or -not $groups[0]) { Write-Output 'NONE: no DTS Mail server in this subscription. Check `az account show`, or run /dts-mail:setup.'; exit 1 }
    if ($groups.Count -gt 1) { Write-Output "MANY: more than one: $($groups -join ', '). Run again with -ResourceGroup <name>."; exit 2 }
    $ResourceGroup = $groups[0]
}

$app = Get-DtsApp $ResourceGroup
if (-not $app) { Write-Output "NONE: no DTS Mail Function App in $ResourceGroup."; exit 1 }
$settings = Get-DtsAppSettings $ResourceGroup $app.Name
$swa = @(Invoke-Az staticwebapp list -g $ResourceGroup --query "[?tags.app=='dts-mail'].{name:name, host:defaultHostname}" -o json)

$values = @{
    resourceGroup = $ResourceGroup
    functionAppName = $app.Name
    apiBaseUrl = $app.ApiBase
    cloudflareAccountId = $settings['CLOUDFLARE_ACCOUNT_ID']
    subscriptionId = (Invoke-Az account show --query id -o tsv -Raw)
}
if ($swa.Count -gt 0 -and $swa[0]) { $values['staticWebAppName'] = $swa[0].name; $values['staticWebAppHostname'] = $swa[0].host }
if ($settings['WEB_APP_URL']) {
    $values['webAppUrl'] = $settings['WEB_APP_URL']
    $h = ([Uri]$settings['WEB_APP_URL']).Host
    if ($swa.Count -eq 0 -or $h -ne $swa[0].host) { $values['webHost'] = $h }
}
Set-DtsState $values
Write-Output 'OK: found the server.'
$values | ConvertTo-Json | Write-Output
