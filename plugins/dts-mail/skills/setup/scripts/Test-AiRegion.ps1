# Checks whether a region can host DTS Mail's AI models in THIS subscription: each model offered (as an AI Services
# deployment) and enough free quota for it. Pick the deployment type per model: Global Standard where offered,
# else Data Zone Standard (Decision-1 is often Data Zone only).
#
#   Test-AiRegion.ps1 -Location eastus2
#   Test-AiRegion.ps1 -Location eastus2,swedencentral,westus3     # compare several; the first that fits is saved
#
# Saves the first region that fits (aiLocation + deployment types) for Deploy-Infra.ps1 -WithAi.
param(
    [Parameter(Mandatory = $true)][string[]]$Location,
    [int]$DecisionCapacity = 50,
    [int]$SmallModelCapacity = 100,
    [int]$LargeModelCapacity = 100
)
. (Join-Path $PSScriptRoot 'Common.ps1')

# powershell.exe -File passes "a,b,c" as one string.
$Location = @($Location | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$wanted = @(
    @{ Key = 'decision'; Name = 'Microsoft-Decision-1'; Format = 'Microsoft'; Version = '1'; Capacity = $DecisionCapacity; UsagePrefix = 'AIServices' },
    @{ Key = 'small'; Name = 'gpt-5.4-nano'; Format = 'OpenAI'; Version = '2026-03-17'; Capacity = $SmallModelCapacity; UsagePrefix = 'OpenAI' },
    @{ Key = 'large'; Name = 'gpt-5.4-mini'; Format = 'OpenAI'; Version = '2026-03-17'; Capacity = $LargeModelCapacity; UsagePrefix = 'OpenAI' }
)
$skuOrder = @('GlobalStandard', 'DataZoneStandard')

$rows = New-Object System.Collections.Generic.List[object]
$chosen = $null
foreach ($loc in $Location) {
    $loc = $loc.Trim().ToLowerInvariant()
    try {
        $models = @(Invoke-Az cognitiveservices model list -l $loc --query "[?kind=='AIServices']" -o json)
        $usage = @(Invoke-Az cognitiveservices usage list -l $loc -o json)
    } catch {
        $rows.Add([pscustomobject]@{ Region = $loc; Model = '-'; Type = '-'; FreeQuota = '-'; Result = 'FAIL'; Note = $_.Exception.Message })
        continue
    }
    $fits = $true
    $skus = @{}
    foreach ($w in $wanted) {
        $m = @($models | Where-Object { $_ -and $_.model.name -eq $w.Name -and $_.model.format -eq $w.Format -and "$($_.model.version)" -eq $w.Version }) | Select-Object -First 1
        if (-not $m) {
            $rows.Add([pscustomobject]@{ Region = $loc; Model = $w.Name; Type = '-'; FreeQuota = '-'; Result = 'FAIL'; Note = 'not offered in this region' })
            $fits = $false; continue
        }
        $offered = @($m.model.skus | ForEach-Object { $_.name })
        # First deployment type that's offered and has enough quota (or doesn't report quota).
        $pick = $null
        $why = "only $($offered -join ', ') offered"
        foreach ($s in $skuOrder) {
            if ($pick -or $offered -notcontains $s) { continue }
            $u = @($usage | Where-Object { $_ -and $_.name.value -eq "$($w.UsagePrefix).$s.$($w.Name)" }) | Select-Object -First 1
            if (-not $u) { $pick = @{ Sku = $s; Free = 'unknown'; Note = 'quota not reported; the deployment will tell' }; continue }
            $free = [int]([double]$u.limit - [double]$u.currentValue)
            if ($free -ge $w.Capacity) { $pick = @{ Sku = $s; Free = $free; Note = '' } }
            else { $why = "$s needs $($w.Capacity), quota left $free (request more in Azure AI Foundry > Quota)" }
        }
        if (-not $pick) {
            $rows.Add([pscustomobject]@{ Region = $loc; Model = $w.Name; Type = '-'; FreeQuota = '-'; Result = 'FAIL'; Note = $why })
            $fits = $false; continue
        }
        $skus[$w.Key] = $pick.Sku
        $rows.Add([pscustomobject]@{ Region = $loc; Model = $w.Name; Type = $pick.Sku; FreeQuota = $pick.Free; Result = 'OK'; Note = $pick.Note })
    }
    if ($fits -and -not $chosen) { $chosen = @{ location = $loc; skus = $skus } }
}

$rows | Format-Table -AutoSize | Out-String -Width 220 | Write-Output
if ($chosen) {
    Set-DtsState @{
        aiLocation = $chosen.location
        aiDecisionSku = $chosen.skus['decision']; aiSmallSku = $chosen.skus['small']; aiLargeSku = $chosen.skus['large']
        aiDecisionCapacity = $DecisionCapacity; aiSmallCapacity = $SmallModelCapacity; aiLargeCapacity = $LargeModelCapacity
    }
    Write-Output "OK: $($chosen.location) can host all three models; saved for Deploy-Infra.ps1 -WithAi."
    exit 0
}
Write-Output 'FAIL: none of these regions can host all three models with the current quota. Try other regions (e.g. eastus2, swedencentral, westus3, eastus, northcentralus), lower the capacities, or request quota.'
exit 1
