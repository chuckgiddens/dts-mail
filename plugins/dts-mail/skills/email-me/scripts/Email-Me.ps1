# Emails the user from Claude Code through their DTS Mail server, with a send-only API token (Windows; Mac and
# Linux use email_me.py). The token is typed into a masked dialog and kept with DPAPI, never shown in the chat.
#
#   Email-Me.ps1 -Action setup -Email you@example.com [-Api https://<app>.azurewebsites.net/api]
#   Email-Me.ps1 -Action status
#   Email-Me.ps1 -Action allow -Email someone@example.com
#   Email-Me.ps1 -Action send -Subject "..." -Html body.html [-Text body.txt] [-To a@x.com,b@y.com] [-Attach f1,f2]
#
# Config: %LOCALAPPDATA%\DtsMail\email-me.json and email-me.secret. Mail only goes to the "allowed" addresses; the
# first one is the default.
param(
    [Parameter(Mandatory = $true)][ValidateSet('setup', 'status', 'allow', 'send')][string]$Action,
    [string]$Email,
    [string]$Api,
    [string]$Subject,
    [string]$Html,
    [string]$Text,
    [string[]]$To,
    [string[]]$Attach
)
. (Join-Path $PSScriptRoot '..\..\setup\scripts\Common.ps1')

# -File passes "a,b" as one string: split lists ourselves.
$To = @($To | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() })
$Attach = @($Attach | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() })

$configFile = Join-Path $script:DtsHome 'email-me.json'
$defaultApi = 'https://dts-email-ingest.azurewebsites.net/api'
$maxAttachmentBytes = 50MB

function Fail([string]$Message, [int]$Code = 1) { Write-Output "FAIL: $Message"; exit $Code }

function Get-Config {
    $token = Get-DtsSecret 'email-me'
    if (-not (Test-Path $configFile) -or -not $token) { Fail 'not set up yet. Run Email-Me.ps1 -Action setup -Email <your address>.' 3 }
    return @{ Config = (Get-Content $configFile -Raw | ConvertFrom-Json); Token = $token }
}

function Save-Config($Config) { $Config | ConvertTo-Json | Set-Content -Path $configFile -Encoding UTF8 }

# The server from the domain's `_dtsmail` TXT record (v=dtsmail1 api=<url>), or $null. Same rules as the apps.
function Find-Server([string]$Address) {
    $domain = $Address.Trim().ToLowerInvariant().Split('@')[-1].TrimEnd('.')
    if ($domain -notmatch '^[a-z0-9.-]+\.[a-z]{2,}$') { return $null }
    try {
        $dns = Invoke-RestMethod -Uri "https://cloudflare-dns.com/dns-query?name=_dtsmail.$domain&type=TXT" `
            -Headers @{ accept = 'application/dns-json' } -TimeoutSec 5
    } catch { return $null }
    if ($dns.Status -ne 0 -or -not $dns.PSObject.Properties['Answer']) { return $null }
    foreach ($a in @($dns.Answer)) {
        if ($a.type -ne 16) { continue }
        $value = ($a.data.Trim().Trim('"') -replace '"\s*"', '').Trim()
        $parts = $value -split '\s+'
        if ($parts[0] -ne 'v=dtsmail1') { continue }
        $apiPart = $parts | Where-Object { $_ -like 'api=*' } | Select-Object -First 1
        if ($apiPart -and $apiPart.Substring(4) -like 'https://*') { return $apiPart.Substring(4).TrimEnd('/') }
    }
    return $null
}

function Send-DtsMail([string]$ApiBase, [string]$Token, [hashtable]$Body) {
    $json = $Body | ConvertTo-Json -Depth 5 -Compress
    try {
        $result = Invoke-RestMethod -Method Post -Uri ($ApiBase.TrimEnd('/') + '/messages/send') `
            -Headers @{ Authorization = "Bearer $Token" } -ContentType 'application/json; charset=utf-8' `
            -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 120
        return @{ Status = 201; Body = $result }
    } catch {
        return Get-DtsHttpError $_
    }
}

# Plain-text version of the HTML body, for mail apps that don't show HTML.
function ConvertTo-PlainText([string]$Markup) {
    $t = $Markup -replace '(?is)<(style|script|head)[^>]*>.*?</\1>', ''
    $t = $t -replace '(?i)<li[^>]*>', "`n- "
    $t = $t -replace '(?i)<(br|/?p|/?div|/?h[1-6]|/?tr|/?table|/?ul|/?ol|hr)[^>]*>', "`n"
    $t = [Net.WebUtility]::HtmlDecode(($t -replace '<[^>]+>', ''))
    $lines = $t -split "`r?`n" | ForEach-Object { ($_ -replace '[ \t]+', ' ').Trim() }
    return (($lines -join "`n") -replace "`n{3,}", "`n`n").Trim() + "`n"
}

switch ($Action) {
    'setup' {
        if (-not $Email -or $Email -notlike '*@*') { Fail 'pass -Email <your address>.' }
        $Email = $Email.Trim().ToLowerInvariant()
        if (-not $Api) { $Api = Find-Server $Email }
        if (-not $Api) { $Api = $defaultApi }
        Write-Output "Server: $Api"
        $token = & (Join-Path $PSScriptRoot '..\..\setup\scripts\Read-Secret.ps1') -Title 'DTS Mail' `
            -Prompt 'Paste your send-only API token (dts_...). Create it in the DTS Mail app: Settings > API tokens.'
        if (-not $token.StartsWith('dts_')) { Fail 'API tokens start with dts_.' }
        Save-DtsSecret 'email-me' $token

        $allowed = @($Email)
        if (Test-Path $configFile) {
            $previous = Get-Content $configFile -Raw | ConvertFrom-Json
            $allowed += @($previous.allowed | Where-Object { $_ -and $_ -ne $Email })
        }
        Save-Config ([ordered]@{ email = $Email; api = $Api; allowed = $allowed })

        $r = Send-DtsMail $Api $token @{
            to = @($Email); subject = 'Claude can now email you'
            text = "This is a test from the DTS Mail email-me skill. Ask Claude to `"email me`" anything.`n"
            html = '<p>This is a test from the DTS Mail <b>email-me</b> skill.</p><p>Ask Claude to &ldquo;email me&rdquo; anything.</p>'
        }
        if ($r.Status -ge 300 -or $r.Status -eq 0) { Fail "the test email was not sent ($($r.Status): $($r.Body)). Check the token, then run setup again." }
        Write-Output "OK: set up. A test email is on its way to $Email."
    }
    'status' {
        $c = Get-Config
        Write-Output 'OK: set up.'
        [ordered]@{ email = $c.Config.email; api = $c.Config.api; allowed = @($c.Config.allowed); token = 'saved' } |
            ConvertTo-Json | Write-Output
    }
    'allow' {
        $c = Get-Config
        if (-not $Email -or $Email -notlike '*@*') { Fail 'pass -Email <address to allow>.' }
        $address = $Email.Trim().ToLowerInvariant()
        $allowed = @($c.Config.allowed)
        if ($allowed -notcontains $address) { $allowed += $address }
        Save-Config ([ordered]@{ email = $c.Config.email; api = $c.Config.api; allowed = $allowed })
        Write-Output "OK: $address can now receive email from Claude. Allowed: $($allowed -join ', ')"
    }
    'send' {
        $c = Get-Config
        if (-not $Subject -or -not $Html) { Fail 'pass -Subject and -Html <file>.' }
        $allowed = @($c.Config.allowed | ForEach-Object { $_.ToLowerInvariant() })
        $recipients = @(if ($To.Count -gt 0) { $To | ForEach-Object { $_.Trim().ToLowerInvariant() } } else { $allowed[0] })
        $blocked = @($recipients | Where-Object { $allowed -notcontains $_ })
        if ($blocked.Count -gt 0) {
            Fail "not an allowed recipient: $($blocked -join ', '). Allowed: $($allowed -join ', '). The user can add one with: Email-Me.ps1 -Action allow -Email <address>" 4
        }

        $markup = [IO.File]::ReadAllText((Resolve-Path $Html))
        $plain = if ($Text) { [IO.File]::ReadAllText((Resolve-Path $Text)) } else { ConvertTo-PlainText $markup }
        $body = @{ to = [object[]]$recipients; subject = $Subject; text = $plain; html = $markup }

        if ($Attach.Count -gt 0) {
            $files = @()
            foreach ($path in $Attach) {
                $item = Get-Item $path.Trim()
                if ($item.Length -gt $maxAttachmentBytes) { Fail "$path is $([int]($item.Length / 1MB)) MB; the limit is 50 MB per file." }
                $type = switch -Regex ($item.Extension.ToLowerInvariant()) {
                    '^\.pdf$' { 'application/pdf' } '^\.png$' { 'image/png' } '^\.jpe?g$' { 'image/jpeg' }
                    '^\.(txt|log|md)$' { 'text/plain' } '^\.csv$' { 'text/csv' } '^\.html?$' { 'text/html' }
                    '^\.json$' { 'application/json' } '^\.zip$' { 'application/zip' }
                    '^\.xlsx$' { 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }
                    '^\.docx$' { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
                    default { 'application/octet-stream' }
                }
                $files += @{ fileName = $item.Name; contentType = $type; contentBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($item.FullName)) }
            }
            $body.attachments = $files
        }

        $r = Send-DtsMail $c.Config.api $c.Token $body
        if ($r.Status -eq 401) { Fail 'the token was refused (revoked or expired). Create a new one and run setup again.' }
        if ($r.Status -ge 300 -or $r.Status -eq 0) { Fail "$($r.Status): $($r.Body)" }
        Write-Output "OK: sent `"$Subject`" to $($recipients -join ', ')."
    }
}
