# Downloads the DTS Mail desktop app for Windows, checks its digital signature, and starts the installer.
# The installed app updates itself from the same place.
#
#   Install-Desktop.ps1
. (Join-Path $PSScriptRoot 'Common.ps1')

$url = 'https://dtsmailreleases.blob.core.windows.net/desktop/DTS-Mail-Setup-x64.exe'
$file = Join-Path $env:TEMP 'DTS-Mail-Setup-x64.exe'
Write-Output "Downloading $url ..."
Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 600
$size = [math]::Round((Get-Item $file).Length / 1MB, 1)

$sig = Get-AuthenticodeSignature -FilePath $file
$signer = ''
if ($sig.SignerCertificate) { $signer = $sig.SignerCertificate.Subject }
if ($sig.Status -ne 'Valid') {
    Write-Output "WARN: the installer's signature is '$($sig.Status)' ($signer). Not starting it; ask Chuck before installing."
    exit 1
}
Write-Output "Signature valid: $signer ($size MB)."
Start-Process -FilePath $file
Write-Output 'OK: the installer is open. Follow its steps; DTS Mail starts when it finishes.'
