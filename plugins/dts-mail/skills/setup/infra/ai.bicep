// Optional AI for DTS Mail: the junk filter (Decision-1) and the writing/summary assistant (gpt-5.4 nano + mini).
// The friend's OWN Azure AI Foundry resource, in their subscription. A separate deployment so a quota or region
// problem here never blocks the mail server, and its region may differ from the server's.
// scripts/Test-AiRegion.ps1 picks a region where all three models are offered and have quota, and the deployment
// type per model (Global Standard where offered, else Data Zone Standard — Decision-1 is often Data Zone only).
// The key is not an output: Deploy-Infra.ps1 reads it with `az cognitiveservices account keys list`.

targetScope = 'resourceGroup'

@description('Region for the AI account (chosen by Test-AiRegion.ps1; may differ from the mail server region).')
param location string = 'eastus2'

@description('AI Services account name; also its endpoint subdomain, so it must be globally unique.')
@minLength(2)
@maxLength(64)
param accountName string = 'dtsmail-ai-${uniqueString(resourceGroup().id)}'

@description('Deployment types, as offered in the region.')
@allowed([ 'GlobalStandard', 'DataZoneStandard' ])
param decisionSku string = 'DataZoneStandard'
@allowed([ 'GlobalStandard', 'DataZoneStandard' ])
param smallModelSku string = 'GlobalStandard'
@allowed([ 'GlobalStandard', 'DataZoneStandard' ])
param largeModelSku string = 'GlobalStandard'

@description('Capacity in thousands of tokens per minute. Modest defaults that fit a new subscription\'s quota; raise them later in Azure AI Foundry (Deployments > Edit) or by re-running with larger values.')
param decisionCapacity int = 50
param smallModelCapacity int = 100
param largeModelCapacity int = 100

var tags = { app: 'dts-mail' }

resource ai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
  }
}

// One at a time: parallel deployment changes on one account conflict.
resource decision 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: ai
  name: 'Decision-1'
  sku: { name: decisionSku, capacity: decisionCapacity }
  properties: {
    model: { format: 'Microsoft', name: 'Microsoft-Decision-1', version: '1' }
  }
}

resource small 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: ai
  name: 'gpt-5.4-nano'
  sku: { name: smallModelSku, capacity: smallModelCapacity }
  properties: {
    model: { format: 'OpenAI', name: 'gpt-5.4-nano', version: '2026-03-17' }
  }
  dependsOn: [ decision ]
}

resource large 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: ai
  name: 'gpt-5.4-mini'
  sku: { name: largeModelSku, capacity: largeModelCapacity }
  properties: {
    model: { format: 'OpenAI', name: 'gpt-5.4-mini', version: '2026-03-17' }
  }
  dependsOn: [ small ]
}

output accountName string = ai.name
output endpoint string = 'https://${accountName}.services.ai.azure.com'
