# Creates or updates the friend's Azure resources from infra/main.bicep (and infra/ai.bicep with -WithAi).
#
# Safe to re-run: secrets the server already has are passed back unchanged, settings the template doesn't manage
# are kept, and only missing secrets are generated. Secrets travel in a temporary parameters file that is deleted
# when the deployment ends; nothing secret is printed.
#
#   Deploy-Infra.ps1 -ResourceGroup dtsmail -Location eastus2 -CustomWebHost mail.example.com [-WithAi [-AiLocation swedencentral]]
#
# AI is always the friend's own Azure AI Foundry resource in their subscription (infra/ai.bicep), never shared.
param(
    [string]$ResourceGroup,
    [string]$Location,
    [string]$StaticWebAppLocation,
    [string]$CustomWebHost,
    [switch]$WithAi,
    [switch]$RemoveAi,
    [string]$AiLocation,          # region for the AI account; default: the one Test-AiRegion.ps1 saved, else eastus2
    [string]$AutoUpdate,          # 'true' | 'false'; empty keeps the current value (default true)
    [string]$ApiPackageUrl        # empty: the latest release in the manifest
)
. (Join-Path $PSScriptRoot 'Common.ps1')

$infra = Join-Path (Split-Path $PSScriptRoot -Parent) 'infra'
$state = Get-DtsState
$ResourceGroup = Get-DtsResourceGroup $ResourceGroup
if (-not $Location) { $Location = $state['location'] }
if (-not $Location) { $Location = 'eastus2' }
if (-not $StaticWebAppLocation) { $StaticWebAppLocation = $state['staticWebAppLocation'] }
if (-not $StaticWebAppLocation) { $StaticWebAppLocation = 'eastus2' }
if ($PSBoundParameters.ContainsKey('CustomWebHost') -eq $false -and $state['webHost']) { $CustomWebHost = $state['webHost'] }

# Resource group.
$exists = Invoke-Az group exists -n $ResourceGroup -Raw
if ($exists -ne 'true') {
    Write-Output "Creating resource group $ResourceGroup in $Location..."
    $null = Invoke-Az group create -n $ResourceGroup -l $Location --tags app=dts-mail -o json
}

# Current server (if any): its settings are the source of truth for secrets.
$app = Get-DtsApp $ResourceGroup
$current = @{}
if ($app) { $current = Get-DtsAppSettings $ResourceGroup $app.Name; Write-Output "Updating existing server $($app.Name)." }
else { Write-Output 'No server yet: creating one.' }

function Keep-Or([string]$Name, [scriptblock]$New) {
    if ($current.ContainsKey($Name) -and $current[$Name]) { return $current[$Name] }
    return & $New
}
$ingestKey = Keep-Or 'INGEST_KEY' { New-DtsKey 32 -Base64Url }
$jwtKey = Keep-Or 'JWT_SIGNING_KEY' { New-DtsKey 48 -Base64Url }
$mfaKey = Keep-Or 'MFA_ENCRYPTION_KEY' { New-DtsKey 32 }
$setupKey = Keep-Or 'SETUP_KEY' { New-DtsKey 32 -Base64Url }

# Cloudflare: a token typed during this setup wins over the one the server has.
$cfToken = Get-DtsSecret 'cloudflare'
if (-not $cfToken) { $cfToken = $current['CLOUDFLARE_API_TOKEN'] }
if (-not $cfToken) { throw 'No Cloudflare token. Run Set-CloudflareToken.ps1 first.' }
$cfAccount = $state['cloudflareAccountId']
if (-not $cfAccount) { $cfAccount = $current['CLOUDFLARE_ACCOUNT_ID'] }
if (-not $cfAccount) { throw 'No Cloudflare account ID. Run Set-CloudflareToken.ps1 first.' }

if (-not $AutoUpdate) { $AutoUpdate = $current['AUTO_UPDATE'] }
if (-not $AutoUpdate) { $AutoUpdate = 'true' }
$autoUpdateBool = ($AutoUpdate -eq 'true')

if (-not $ApiPackageUrl) {
    $manifest = Get-DtsManifest
    if ($manifest.schema -ne 1) { throw "Unexpected release manifest schema '$($manifest.schema)'. Update the dts-mail plugin." }
    $ApiPackageUrl = $manifest.api.url
    Write-Output "Server release: $($manifest.api.version)"
}

# AI (optional, its own deployment so a quota problem never blocks the mail server).
$aiEndpoint = ''
$aiKey = ''
$aiReady = $false
if ($WithAi) {
    # Check the region first (models offered + quota), unless Test-AiRegion.ps1 already approved this one.
    if (-not $AiLocation) { $AiLocation = $state['aiLocation'] }
    if (-not $AiLocation) { $AiLocation = 'eastus2' }
    if ($state['aiLocation'] -ne $AiLocation -or -not $state['aiDecisionSku']) {
        & (Join-Path $PSScriptRoot 'Test-AiRegion.ps1') -Location $AiLocation | Write-Output
        $state = Get-DtsState
        $aiReady = ($LASTEXITCODE -eq 0)
    } else { $aiReady = $true }
    if (-not $aiReady) { Write-Output "WARN: $AiLocation can't host the AI models right now; continuing without AI. Try Test-AiRegion.ps1 with other regions, then Deploy-Infra.ps1 -WithAi -AiLocation <region>." }
}
if ($aiReady) {
    $aiAccounts = Invoke-Az cognitiveservices account list -g $ResourceGroup --query "[?tags.app=='dts-mail'].name" -o json
    $aiParams = @('deployment', 'group', 'create', '-g', $ResourceGroup, '-n', "dtsmail-ai-$(Get-Date -Format yyyyMMddHHmmss)",
        '-f', (Join-Path $infra 'ai.bicep'), '-p', "location=$AiLocation",
        '-p', "decisionSku=$($state['aiDecisionSku'])", '-p', "smallModelSku=$($state['aiSmallSku'])", '-p', "largeModelSku=$($state['aiLargeSku'])",
        '-p', "decisionCapacity=$($state['aiDecisionCapacity'])", '-p', "smallModelCapacity=$($state['aiSmallCapacity'])", '-p', "largeModelCapacity=$($state['aiLargeCapacity'])",
        '--query', 'properties.outputs', '-o', 'json')
    if ($aiAccounts -and @($aiAccounts).Count -gt 0) { $aiParams += @('-p', "accountName=$(@($aiAccounts)[0])") }
    Write-Output "Deploying your AI models in $AiLocation (a few minutes)..."
    try {
        $aiOut = Invoke-Az @aiParams
        $aiEndpoint = $aiOut.endpoint.value
        $aiKey = Invoke-Az cognitiveservices account keys list -g $ResourceGroup -n $aiOut.accountName.value --query key1 -o tsv -Raw
        Set-DtsState @{ ai = $true; aiAccountName = $aiOut.accountName.value; aiLocation = $AiLocation }
        Write-Output "AI ready at $aiEndpoint (your own AI Foundry resource)."
    } catch {
        Write-Output "WARN: AI could not be set up, continuing without it. $($_.Exception.Message)"
    }
}
# Keep AI the server already has (also when a -WithAi re-check failed); -RemoveAi turns it off.
if (-not $aiEndpoint -and -not $RemoveAi -and $current['AI_ENDPOINT']) {
    $aiEndpoint = $current['AI_ENDPOINT']
    $aiKey = $current['AI_KEY']
    # Re-read the key from their AI account: it may have been regenerated (the cause of AI 401s).
    try {
        $acct = @(Invoke-Az cognitiveservices account list -g $ResourceGroup --query "[?tags.app=='dts-mail'].name" -o json) | Select-Object -First 1
        if ($acct) { $aiKey = Invoke-Az cognitiveservices account keys list -g $ResourceGroup -n $acct --query key1 -o tsv -Raw }
    } catch { }
}

# Settings this template doesn't manage pass through untouched.
$managed = @('AzureWebJobsStorage', 'EmailStorage', 'DEPLOYMENT_STORAGE_CONNECTION_STRING', 'APPLICATIONINSIGHTS_CONNECTION_STRING',
    'INGEST_KEY', 'JWT_SIGNING_KEY', 'MFA_ENCRYPTION_KEY', 'SETUP_KEY', 'CORS_ORIGINS', 'WEB_APP_URL', 'RELEASE_MANIFEST_URL',
    'AUTO_UPDATE', 'DTS_INFRA_VERSION', 'DTS_SUBSCRIPTION_ID', 'DTS_RESOURCE_GROUP', 'CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID',
    'CLOUDFLARE_EMAIL_WORKER', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASSWORD',
    'AI_ENDPOINT', 'AI_KEY', 'AI_DEPLOYMENT', 'AI_MODEL_SMALL', 'AI_MODEL_LARGE')
$extra = @{}
foreach ($k in $current.Keys) { if ($managed -notcontains $k) { $extra[$k] = "$($current[$k])" } }

$parameters = @{
    location = @{ value = $Location }
    staticWebAppLocation = @{ value = $StaticWebAppLocation }
    customWebHost = @{ value = "$CustomWebHost" }
    apiPackageUrl = @{ value = $ApiPackageUrl }
    autoUpdate = @{ value = $autoUpdateBool }
    ingestKey = @{ value = $ingestKey }
    jwtSigningKey = @{ value = $jwtKey }
    mfaEncryptionKey = @{ value = $mfaKey }
    setupKey = @{ value = $setupKey }
    cloudflareApiToken = @{ value = $cfToken }
    cloudflareAccountId = @{ value = $cfAccount }
    aiEndpoint = @{ value = $aiEndpoint }
    aiKey = @{ value = "$aiKey" }
    extraAppSettings = @{ value = $extra }
}
if ($app) { $parameters['baseName'] = @{ value = $app.Name } }

$file = Join-Path $env:TEMP ("dtsmail-params-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $doc = @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'; contentVersion = '1.0.0.0'; parameters = $parameters }
    [IO.File]::WriteAllText($file, ($doc | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
    Write-Output 'Deploying the server (usually 3-8 minutes)...'
    $out = Invoke-Az deployment group create -g $ResourceGroup -n "dtsmail-$(Get-Date -Format yyyyMMddHHmmss)" `
        -f (Join-Path $infra 'main.bicep') -p "@$file" --query properties.outputs -o json
} finally {
    Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
}

$result = @{
    resourceGroup = $ResourceGroup
    location = $Location
    staticWebAppLocation = $StaticWebAppLocation
    webHost = "$CustomWebHost"
    functionAppName = $out.functionAppName.value
    apiBaseUrl = $out.apiBaseUrl.value
    staticWebAppName = $out.staticWebAppName.value
    staticWebAppHostname = $out.staticWebAppHostname.value
    webAppUrl = $out.webAppUrl.value
    infraVersion = $out.infraVersion.value
    subscriptionId = (Invoke-Az account show --query id -o tsv -Raw)
}
Set-DtsState $result
Write-Output 'OK: deployment finished.'
$result | ConvertTo-Json | Write-Output
