# Waits until the new server answers GET /api/version (a fresh Flex Consumption app takes a few minutes to start).
#
#   Wait-DtsServer.ps1 [-ResourceGroup dtsmail] [-Minutes 10]
param([string]$ResourceGroup, [int]$Minutes = 10)
. (Join-Path $PSScriptRoot 'Common.ps1')

$ResourceGroup = Get-DtsResourceGroup $ResourceGroup
$app = Get-DtsApp $ResourceGroup
if (-not $app) { throw "No DTS Mail server in resource group $ResourceGroup." }

$deadline = (Get-Date).AddMinutes($Minutes)
$last = ''
while ((Get-Date) -lt $deadline) {
    try {
        $v = Invoke-RestMethod -Uri "$($app.ApiBase)/version" -TimeoutSec 30
        Write-Output "OK: server $($app.Name) is running version $($v.version)."
        $v | ConvertTo-Json -Depth 5 | Write-Output
        exit 0
    } catch {
        $e = Get-DtsHttpError $_
        $msg = "not ready yet ($($e.Status))"
        if ($msg -ne $last) { Write-Output $msg; $last = $msg }
    }
    Start-Sleep -Seconds 15
}
Write-Output "FAIL: the server didn't answer within $Minutes minutes. Check the deployment in the Azure portal (resource group $ResourceGroup > Deployments) and troubleshooting.md."
exit 1
