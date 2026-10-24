# Shows a small masked input window and returns what was typed or pasted. Used by the other scripts so secrets go
# straight from the user's clipboard into a variable, never into Claude's conversation.
#
#   $token = & (Join-Path $PSScriptRoot 'Read-Secret.ps1') -Title 'Cloudflare' -Prompt 'Paste your Cloudflare API token'
#
# Don't call it directly from Claude: its output is the secret. Call a script that uses it.
param(
    [string]$Title = 'DTS Mail',
    [string]$Prompt = 'Paste the value and press OK:'
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.Size = New-Object System.Drawing.Size(460, 170)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = $Prompt
$label.Location = New-Object System.Drawing.Point(12, 12)
$label.Size = New-Object System.Drawing.Size(420, 34)
$form.Controls.Add($label)

$box = New-Object System.Windows.Forms.TextBox
$box.Location = New-Object System.Drawing.Point(12, 50)
$box.Size = New-Object System.Drawing.Size(420, 24)
$box.UseSystemPasswordChar = $true
$form.Controls.Add($box)

$ok = New-Object System.Windows.Forms.Button
$ok.Text = 'OK'
$ok.Location = New-Object System.Drawing.Point(276, 90)
$ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($ok)
$form.AcceptButton = $ok

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Location = New-Object System.Drawing.Point(357, 90)
$cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($cancel)
$form.CancelButton = $cancel

$form.Add_Shown({ $form.Activate(); $box.Focus() })
$result = $form.ShowDialog()
$value = $box.Text.Trim()
$form.Dispose()

if ($result -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrEmpty($value)) {
    throw 'Cancelled: nothing was entered.'
}
return $value
