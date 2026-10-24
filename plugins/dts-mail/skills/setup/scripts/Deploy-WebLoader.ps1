# Publishes the web loader (../web-loader) to the friend's Static Web App with a config.json pointing at their server.
# The loader then fetches the web app build that matches their server on every visit, so this only needs re-running
# when the plugin ships a new loader or the server address changes. Needs Node.js (npx) for the Static Web Apps CLI.
#
#   Deploy-WebLoader.ps1 [-ResourceGroup dtsmail]
param([string]$ResourceGroup)
. (Join-Path $PSScriptRoot 'Common.ps1')

$ResourceGroup = Get-DtsResourceGroup $ResourceGroup
$state = Get-DtsState
$app = Get-DtsApp $ResourceGroup
if (-not $app) { throw "No DTS Mail server in resource group $ResourceGroup. Run Deploy-Infra.ps1 first." }
$swa = $state['staticWebAppName']
if (-not $swa) {
    $found = Invoke-Az staticwebapp list -g $ResourceGroup --query "[?tags.app=='dts-mail'].name" -o json
    if ($found) { $swa = @($found)[0] }
}
if (-not $swa) { throw "No Static Web App found in $ResourceGroup. Run Deploy-Infra.ps1 first." }

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'web-loader'
if (-not (Test-Path (Join-Path $source 'index.html'))) { throw "The web loader files are missing from the plugin ($source). Update the dts-mail plugin." }
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { throw 'Node.js is not installed (npx not found). Install Node.js LTS, open a new terminal, and run this again.' }

$work = Join-Path $env:TEMP ('dtsmail-web-' + [guid]::NewGuid().ToString('N'))
try {
    Copy-Item -Path $source -Destination $work -Recurse
    $config = @{ apiBaseUrl = $app.ApiBase } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $work 'config.json'), $config, (New-Object Text.UTF8Encoding $false))

    # The deployment token goes to the CLI through its environment variable, not the command line or the console.
    $env:SWA_CLI_DEPLOYMENT_TOKEN = Invoke-Az staticwebapp secrets list -n $swa -g $ResourceGroup --query properties.apiKey -o tsv -Raw
    Write-Output "Publishing the web app to $swa..."
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $log = & npx --yes '@azure/static-web-apps-cli@2' deploy $work --env production 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) {
        $log | Select-Object -Last 25 | ForEach-Object { "$_" } | Write-Output
        throw "Static Web Apps deploy failed (exit $code)."
    }
} finally {
    Remove-Item Env:\SWA_CLI_DEPLOYMENT_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
}

$hostName = Invoke-Az staticwebapp show -n $swa -g $ResourceGroup --query defaultHostname -o tsv -Raw
Set-DtsState @{ webLoaderDeployedUtc = (Get-Date).ToUniversalTime().ToString('o') }
Write-Output "OK: web app published. It answers at https://$hostName (and at the custom address once that's set up)."
