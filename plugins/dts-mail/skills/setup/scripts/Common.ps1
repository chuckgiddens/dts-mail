# Shared helpers for the DTS Mail setup scripts. Dot-source it: . (Join-Path $PSScriptRoot 'Common.ps1')
# Works in Windows PowerShell 5.1 and PowerShell 7.
#
# Secrets never go to the console: they live in variables, in Azure app settings, or (during setup only) in files
# under %LOCALAPPDATA%\DtsMail encrypted for this Windows user with DPAPI.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# az prints UTF-8; without this, non-ASCII names in its JSON come out garbled. Hosts without a console refuse it.
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch { }

$script:DtsHome = Join-Path $env:LOCALAPPDATA 'DtsMail'
$script:DtsStateFile = Join-Path $script:DtsHome 'setup.json'
$script:DtsManifestUrl = 'https://dtsmailreleases.blob.core.windows.net/server/stable/manifest.json'
$script:CloudflareApi = 'https://api.cloudflare.com/client/v4'

if (-not (Test-Path $script:DtsHome)) { New-Item -ItemType Directory -Path $script:DtsHome | Out-Null }

# ---------- setup state (non-secret answers and results, so a re-run continues where it stopped) ----------

function ConvertTo-DtsHashtable($obj) {
    $h = @{}
    if ($null -eq $obj) { return $h }
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Get-DtsState {
    if (-not (Test-Path $script:DtsStateFile)) { return @{} }
    return ConvertTo-DtsHashtable (Get-Content $script:DtsStateFile -Raw | ConvertFrom-Json)
}

function Set-DtsState([hashtable]$Values) {
    $state = Get-DtsState
    foreach ($k in $Values.Keys) { $state[$k] = $Values[$k] }
    $json = $state | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($script:DtsStateFile, $json, (New-Object Text.UTF8Encoding $false))
}

# ---------- secrets kept locally during setup (DPAPI, this Windows user only) ----------

function Save-DtsSecret([string]$Name, [string]$Value) {
    $secure = ConvertTo-SecureString $Value -AsPlainText -Force
    ConvertFrom-SecureString $secure | Set-Content -Path (Join-Path $script:DtsHome "$Name.secret") -Encoding ASCII
}

function Get-DtsSecret([string]$Name) {
    $path = Join-Path $script:DtsHome "$Name.secret"
    if (-not (Test-Path $path)) { return $null }
    $secure = (Get-Content $path -Raw).Trim() | ConvertTo-SecureString
    return (New-Object System.Net.NetworkCredential('', $secure)).Password
}

function Remove-DtsSecret([string]$Name) {
    Remove-Item -Path (Join-Path $script:DtsHome "$Name.secret") -ErrorAction SilentlyContinue
}

function New-DtsKey([int]$Bytes = 32, [switch]$Base64Url) {
    $buf = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buf) } finally { $rng.Dispose() }
    $b64 = [Convert]::ToBase64String($buf)
    if ($Base64Url) { return $b64.TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    return $b64
}

# ---------- Azure CLI ----------

# Runs az and returns its output parsed from JSON (or the raw text when the first argument is -Raw). Throws with az's
# error on failure. A plain function on purpose: every argument, -g and -o included, goes to az untouched.
function Invoke-Az {
    $raw = $false
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($a in $args) { if ("$a" -eq '-Raw') { $raw = $true } else { $list.Add("$a") } }
    # 5.1 turns native stderr (az prints warnings there) into terminating errors under 'Stop'.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & az @list 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
    $text = ($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
    $err = ($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) { throw "az $($list[0]) $($list[1]) failed: $err" }
    if ($raw) { return $text.Trim() }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

# The DTS Mail Function App in a resource group (found by its app=dts-mail tag), or $null.
function Get-DtsApp([string]$ResourceGroup) {
    $apps = Invoke-Az functionapp list -g $ResourceGroup --query "[?tags.app=='dts-mail'].{name:name, host:defaultHostName}" -o json
    if (-not $apps) { return $null }
    $a = @($apps)[0]
    return @{ Name = $a.name; Host = $a.host; ApiBase = "https://$($a.host)/api" }
}

# App settings as a hashtable (values include secrets: never print it).
function Get-DtsAppSettings([string]$ResourceGroup, [string]$Name) {
    $list = Invoke-Az functionapp config appsettings list -g $ResourceGroup -n $Name -o json
    $h = @{}
    foreach ($s in @($list)) { $h[$s.name] = $s.value }
    return $h
}

function Get-DtsResourceGroup([string]$ResourceGroup) {
    if ($ResourceGroup) { return $ResourceGroup }
    $state = Get-DtsState
    if ($state['resourceGroup']) { return $state['resourceGroup'] }
    throw 'No resource group given and none saved yet. Pass -ResourceGroup.'
}

# ---------- HTTP ----------

# Status code and body text from a failed Invoke-RestMethod/Invoke-WebRequest, in 5.1 and 7.
function Get-DtsHttpError($ErrorRecord) {
    $status = 0
    $resp = $null
    if ($ErrorRecord.Exception.PSObject.Properties['Response']) { $resp = $ErrorRecord.Exception.Response }
    if ($resp) { try { $status = [int]$resp.StatusCode } catch { $status = 0 } }
    $body = $null
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { $body = $ErrorRecord.ErrorDetails.Message }
    elseif ($resp -and ($resp -is [System.Net.WebResponse])) {
        try { $reader = New-Object IO.StreamReader($resp.GetResponseStream()); $body = $reader.ReadToEnd() } catch { }
    }
    if (-not $body) { $body = $ErrorRecord.Exception.Message }
    return @{ Status = $status; Body = $body }
}

function Get-DtsManifest {
    return Invoke-RestMethod -Uri $script:DtsManifestUrl -Headers @{ 'Cache-Control' = 'no-cache' } -TimeoutSec 30
}

# ---------- Cloudflare ----------

# The Cloudflare token for this setup: the one typed during setup, else the one the server already has.
function Get-DtsCloudflareToken([string]$ResourceGroup) {
    $t = Get-DtsSecret 'cloudflare'
    if ($t) { return $t }
    if ($ResourceGroup) {
        $app = Get-DtsApp $ResourceGroup
        if ($app) {
            $settings = Get-DtsAppSettings $ResourceGroup $app.Name
            if ($settings['CLOUDFLARE_API_TOKEN']) { return $settings['CLOUDFLARE_API_TOKEN'] }
        }
    }
    throw 'No Cloudflare token yet. Run Set-CloudflareToken.ps1 first.'
}

# Calls the Cloudflare API and returns the "result" (or the whole response with -Full). Throws a readable error.
function Invoke-Cloudflare {
    param([string]$Token, [string]$Method = 'GET', [string]$Path, $Body, [switch]$Full)
    $req = @{ Uri = "$script:CloudflareApi$Path"; Method = $Method; Headers = @{ Authorization = "Bearer $Token" }; TimeoutSec = 60 }
    if ($null -ne $Body) { $req['Body'] = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10)); $req['ContentType'] = 'application/json; charset=utf-8' }
    try { $r = Invoke-RestMethod @req }
    catch {
        $e = Get-DtsHttpError $_
        $msg = $e.Body
        try { $j = $e.Body | ConvertFrom-Json; if ($j.errors) { $msg = ($j.errors | ForEach-Object { "$($_.code): $($_.message)" }) -join '; ' } } catch { }
        throw "Cloudflare $Method $Path failed ($($e.Status)): $msg"
    }
    if ($Full) { return $r }
    return $r.result
}

function Get-DtsZone([string]$Token, [string]$AccountId, [string]$Domain) {
    $zones = Invoke-Cloudflare -Token $Token -Path "/zones?name=$([Uri]::EscapeDataString($Domain))&account.id=$AccountId"
    if (-not $zones -or @($zones).Count -eq 0) { return $null }
    return @($zones)[0]
}

# Creates or updates one DNS record (matched by type + name).
function Set-DtsDnsRecord([string]$Token, [string]$ZoneId, [string]$Type, [string]$Name, [string]$Content, [bool]$Proxied = $false) {
    $existing = Invoke-Cloudflare -Token $Token -Path "/zones/$ZoneId/dns_records?type=$Type&name=$([Uri]::EscapeDataString($Name))"
    $record = @{ type = $Type; name = $Name; content = $Content; ttl = 1 }
    if ($Type -eq 'CNAME' -or $Type -eq 'A') { $record['proxied'] = $Proxied }
    if ($existing -and @($existing).Count -gt 0) {
        $id = @($existing)[0].id
        return Invoke-Cloudflare -Token $Token -Method 'PUT' -Path "/zones/$ZoneId/dns_records/$id" -Body $record
    }
    return Invoke-Cloudflare -Token $Token -Method 'POST' -Path "/zones/$ZoneId/dns_records" -Body $record
}
