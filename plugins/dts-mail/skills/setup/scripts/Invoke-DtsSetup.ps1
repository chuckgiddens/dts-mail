# Calls the server's setup endpoints with the SETUP_KEY read from its app settings (never printed).
# Prints one JSON object: { "status": <http status>, "ok": true|false, "body": <response> }.
#
#   Invoke-DtsSetup.ps1 -Action status
#   Invoke-DtsSetup.ps1 -Action worker
#   Invoke-DtsSetup.ps1 -Action admin -Email bob@example.com -DisplayName "Bob Smith"
#   Invoke-DtsSetup.ps1 -Action domain -Domain example.com [-AdminEmail bob@example.com] [-ReplaceExistingMail]
#   Invoke-DtsSetup.ps1 -Action update
#   Invoke-DtsSetup.ps1 -Action version          # the public /version endpoint, no key needed
#   Invoke-DtsSetup.ps1 -Action health           # public /health: junkDetection (AI) and outboundMail (SMTP)
param(
    [Parameter(Mandatory = $true)][ValidateSet('status', 'worker', 'admin', 'domain', 'update', 'version', 'health')][string]$Action,
    [string]$ResourceGroup,
    [string]$Email,
    [string]$DisplayName,
    [string]$Domain,
    [string]$AdminEmail,
    [switch]$ReplaceExistingMail
)
. (Join-Path $PSScriptRoot 'Common.ps1')

$ResourceGroup = Get-DtsResourceGroup $ResourceGroup
$app = Get-DtsApp $ResourceGroup
if (-not $app) { throw "No DTS Mail server in resource group $ResourceGroup yet. Run Deploy-Infra.ps1 first." }

$headers = @{}
$method = 'POST'
$body = $null
$timeout = 120
switch ($Action) {
    'version' { $method = 'GET'; $uri = "$($app.ApiBase)/version" }
    'health' { $method = 'GET'; $uri = "$($app.ApiBase)/health" }
    'status' { $method = 'GET'; $uri = "$($app.ApiBase)/setup/status" }
    'worker' { $uri = "$($app.ApiBase)/setup/worker" }
    'update' { $uri = "$($app.ApiBase)/setup/update"; $timeout = 300 }
    'admin' {
        if (-not $Email) { throw '-Email is required.' }
        $uri = "$($app.ApiBase)/setup/admin"
        $body = @{ email = $Email.Trim(); displayName = "$DisplayName".Trim() }
    }
    'domain' {
        if (-not $Domain) { throw '-Domain is required.' }
        $uri = "$($app.ApiBase)/setup/domain"
        $body = @{ domain = $Domain.Trim().ToLowerInvariant(); replaceExistingMail = [bool]$ReplaceExistingMail }
        if ($AdminEmail) { $body['adminEmail'] = $AdminEmail.Trim() }
        $timeout = 300 # includes a round-trip test email of up to 2.5 minutes
    }
}
if ($Action -ne 'version' -and $Action -ne 'health') {
    $settings = Get-DtsAppSettings $ResourceGroup $app.Name
    if (-not $settings['SETUP_KEY']) { throw 'The server has no SETUP_KEY setting. Re-run Deploy-Infra.ps1.' }
    $headers['X-Setup-Key'] = $settings['SETUP_KEY']
}

$req = @{ Uri = $uri; Method = $method; Headers = $headers; TimeoutSec = $timeout }
# UTF-8 bytes: Windows PowerShell 5.1 would otherwise send a string body as ISO-8859-1 (think "José").
if ($null -ne $body) { $req['Body'] = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 5)); $req['ContentType'] = 'application/json; charset=utf-8' }

try {
    $r = Invoke-RestMethod @req
    $out = @{ status = 200; ok = $true; body = $r }
} catch {
    $e = Get-DtsHttpError $_
    $parsed = $e.Body
    try { $parsed = $e.Body | ConvertFrom-Json } catch { }
    $out = @{ status = $e.Status; ok = $false; body = $parsed }
}
$out | ConvertTo-Json -Depth 10 | Write-Output
