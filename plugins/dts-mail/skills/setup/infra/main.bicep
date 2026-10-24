// DTS Mail for one friend: everything that runs in their Azure resource group.
//
//   Storage (tables, mail blobs, large attachments, event queues, deployment packages) · Log Analytics + Application Insights
//   Flex Consumption plan + Function App (.NET 8 isolated) running the release package from the public channel
//   Static Web App (Free) for the web loader
//
// Deployed (and re-deployed) by scripts/Deploy-Infra.ps1, which generates the secrets the first time and passes the
// current ones back on every later run. Every app setting the app uses is set here; settings this template doesn't
// know about come in through extraAppSettings so a re-deploy never drops them.

targetScope = 'resourceGroup'

@description('Region for everything except the Static Web App. Must offer Flex Consumption (e.g. eastus2).')
param location string = resourceGroup().location

@description('Base for resource names: letters and digits only, 3-18 characters, globally unique.')
@minLength(3)
@maxLength(18)
param baseName string = 'dtsmail${take(uniqueString(resourceGroup().id), 10)}'

@description('Static Web Apps only run in a few regions.')
@allowed([ 'centralus', 'eastus2', 'westus2', 'westeurope', 'eastasia' ])
param staticWebAppLocation string = 'eastus2'

@description('Custom host name for the web app, e.g. mail.example.com. Empty: only the Static Web App default host.')
param customWebHost string = ''

@description('The API package to run: api.url from the release manifest.')
param apiPackageUrl string

@description('Release manifest the server checks hourly for updates.')
#disable-next-line no-hardcoded-env-urls // the public release channel, not a cloud endpoint
param releaseManifestUrl string = 'https://dtsmailreleases.blob.core.windows.net/server/stable/manifest.json'

@description('false: the server still checks for updates and reports them, but never installs them.')
param autoUpdate bool = true

@secure()
@description('Shared secret between the Cloudflare Email Worker and /api/ingest.')
param ingestKey string

@secure()
@description('HS256 key for sign-in tokens (at least 32 characters).')
param jwtSigningKey string

@secure()
@description('Base64, 32 bytes: encrypts authenticator-app secrets.')
param mfaEncryptionKey string

@secure()
@description('Enables the setup/* endpoints the Claude Code skills call.')
param setupKey string

@secure()
@description('Cloudflare API token (see references/cloudflare-token.md). Also the SMTP password for Email Sending.')
param cloudflareApiToken string

@description('Cloudflare account ID that owns the domain.')
param cloudflareAccountId string

@description('AI Foundry endpoint (output of ai.bicep). Empty: AI features off.')
param aiEndpoint string = ''

@secure()
@description('AI Foundry key. Ignored when aiEndpoint is empty.')
param aiKey string = ''

@description('App settings this template does not manage, kept as they are on re-deploy.')
param extraAppSettings object = {}

var infraVersion = int(trim(loadTextContent('INFRA_VERSION')))
var tags = { app: 'dts-mail' }
var storageName = toLower(baseName)
var deploymentContainer = 'app-package'

// ---------- monitoring ----------

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-logs'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    // A runaway log loop can't turn into a surprise bill.
    workspaceCapping: { dailyQuotaGb: json('0.5') }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

// ---------- web (Static Web App: the loader page) ----------

resource web 'Microsoft.Web/staticSites@2024-04-01' = {
  name: '${baseName}-web'
  location: staticWebAppLocation
  tags: tags
  sku: { name: 'Free', tier: 'Free' }
  properties: {
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Disabled'
  }
}

var webOrigins = concat([ 'https://${web.properties.defaultHostname}' ], empty(customWebHost) ? [] : [ 'https://${customWebHost}' ])
var webAppUrl = empty(customWebHost) ? 'https://${web.properties.defaultHostname}' : 'https://${customWebHost}'

// ---------- storage ----------

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true // the app and the Flex deployment use connection strings
  }
}

// Large attachments: the web app uploads them straight into the private "shared-files" container with a short-lived
// write link (PUT), so the blob service needs CORS for the web app. Downloads use read-only links and need none.
resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: webOrigins
          allowedMethods: [ 'PUT', 'OPTIONS' ]
          allowedHeaders: [ '*' ]
          exposedHeaders: [ '*' ]
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

resource packages 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: deploymentContainer
  properties: { publicAccess: 'None' }
}

// Browsers poll their per-device event queue directly, so the queue service needs CORS for the web app.
resource queues 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: webOrigins
          allowedMethods: [ 'GET', 'DELETE', 'OPTIONS' ]
          allowedHeaders: [ '*' ]
          exposedHeaders: [ '*' ]
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

var storageConnection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

// ---------- API (Flex Consumption Function App) ----------

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${baseName}-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

var managedSettings = {
  AzureWebJobsStorage: storageConnection
  EmailStorage: storageConnection
  DEPLOYMENT_STORAGE_CONNECTION_STRING: storageConnection
  APPLICATIONINSIGHTS_CONNECTION_STRING: insights.properties.ConnectionString
  INGEST_KEY: ingestKey
  JWT_SIGNING_KEY: jwtSigningKey
  MFA_ENCRYPTION_KEY: mfaEncryptionKey
  SETUP_KEY: setupKey
  CORS_ORIGINS: join(webOrigins, ',')
  WEB_APP_URL: webAppUrl
  RELEASE_MANIFEST_URL: releaseManifestUrl
  AUTO_UPDATE: autoUpdate ? 'true' : 'false'
  DTS_INFRA_VERSION: string(infraVersion)
  DTS_SUBSCRIPTION_ID: subscription().subscriptionId
  DTS_RESOURCE_GROUP: resourceGroup().name
  CLOUDFLARE_API_TOKEN: cloudflareApiToken
  CLOUDFLARE_ACCOUNT_ID: cloudflareAccountId
  CLOUDFLARE_EMAIL_WORKER: 'dts-email-ingest'
  SMTP_HOST: 'smtp.mx.cloudflare.net'
  SMTP_PORT: '465'
  SMTP_USER: 'api_token'
  SMTP_PASSWORD: cloudflareApiToken
}

var aiSettings = empty(aiEndpoint) ? {} : {
  AI_ENDPOINT: aiEndpoint
  AI_KEY: aiKey
  AI_DEPLOYMENT: 'Decision-1'
  AI_MODEL_SMALL: 'gpt-5.4-nano'
  AI_MODEL_LARGE: 'gpt-5.4-mini'
}

// Later objects win: managed and AI settings override stale copies in extraAppSettings.
var appSettings = union(extraAppSettings, managedSettings, aiSettings)

resource api 'Microsoft.Web/sites@2024-04-01' = {
  name: baseName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      cors: { allowedOrigins: webOrigins, supportCredentials: false }
      // What the host needs to start; the full list is the appsettings resource below.
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConnection }
        { name: 'DEPLOYMENT_STORAGE_CONNECTION_STRING', value: storageConnection }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainer}'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
          }
        }
      }
      runtime: { name: 'dotnet-isolated', version: '8.0' }
      scaleAndConcurrency: { instanceMemoryMB: 2048, maximumInstanceCount: 40 }
    }
  }
  dependsOn: [ packages ]
}

// The complete app settings (replaces the list on every deploy, which is why extraAppSettings exists).
resource settings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: api
  name: 'appsettings'
  properties: appSettings
}

// The server updates itself (ARM onedeploy) with its own identity, so it may manage its own site and nothing else.
var websiteContributor = 'de139f84-1756-47ae-9be6-808fbbe84772'

resource selfDeploy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(api.id, websiteContributor)
  scope: api
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributor)
    principalId: api.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Installs the release package. Re-deploying this template re-installs whatever apiPackageUrl names.
resource code 'Microsoft.Web/sites/extensions@2024-04-01' = {
  parent: api
  name: 'onedeploy'
  #disable-next-line BCP187 // onedeploy takes packageUri/remoteBuild; the type definition doesn't list them
  properties: {
    packageUri: apiPackageUrl
    remoteBuild: false
  }
  dependsOn: [ settings ]
}

output functionAppName string = api.name
output apiBaseUrl string = 'https://${api.properties.defaultHostName}/api'
output staticWebAppName string = web.name
output staticWebAppHostname string = web.properties.defaultHostname
output storageAccountName string = storage.name
output webAppUrl string = webAppUrl
output infraVersion int = infraVersion
