# DTS Mail for friends — design

Friends run their own copy of DTS Mail in **their own** Azure subscription and Cloudflare account, set up by Claude
Code with the `dts-mail` plugin, and kept current automatically from Chuck's builds. This file is the contract between
the pieces; change it together with them.

```
 Chuck's pipelines ──publish──▶ public release channel (dtsmailreleases storage, container "server")
   backend: after prod deploy + health check     stable/manifest.json
   web:     after prod deploy                    api/<ver>/emailingest.zip    web/<ver>/…
   desktop: (unchanged) container "desktop"      ▲                 ▲
                                                 │ hourly          │ every page load
 Friend's Azure (Bicep)                          │                 │
   Function App (Flex) ── SelfUpdate timer ──────┘                 │
     └ deploys itself via ARM onedeploy (managed identity)         │
   Static Web App ── web loader (index.html + config.json) ────────┘ loads the web build matching the friend's API
   Storage, App Insights, optional AI Foundry
 Friend's Cloudflare
   Email Routing catch-all ─▶ Email Worker "dts-email-ingest" ─▶ Function App /api/ingest
   Email Sending (SMTP relay) ◀── Function App
   DNS: MX/SPF/DKIM/DMARC, _dtsmail TXT (server discovery), mail.<domain> CNAME ─▶ Static Web App
 Friend's PCs: desktop app from Chuck's feed (auto-updates), finds the server from the _dtsmail TXT record
```

## 1. Release channel

Public, read-only: `https://dtsmailreleases.blob.core.windows.net/server/` (container `server`, public blob access,
blob CORS `GET, HEAD, OPTIONS` from `*` so browsers can load the web build as module scripts).

| Path | Written by | Notes |
|---|---|---|
| `stable/manifest.json` | backend + web pipelines (read-modify-write with `If-Match`) | `Cache-Control: no-cache` |
| `api/<version>/emailingest.zip` | backend pipeline, after prod deploy + health check | immutable; contains `release.json` |
| `web/<version>/…` | web pipeline, after prod deploy | immutable; built with `base` = this folder's absolute URL |

Versions are `yyyy.M.d.<BuildId>` (e.g. `2026.10.24.512`), compared part by part as integers. Backend and web have
separate lineages; the only cross-comparison is `web.minApi` against an API version.

```json
{
  "schema": 1,
  "channel": "stable",
  "updatedUtc": "2026-10-24T12:00:00Z",
  "api": {
    "version": "2026.10.24.512",
    "url": "https://dtsmailreleases.blob.core.windows.net/server/api/2026.10.24.512/emailingest.zip",
    "sha256": "<64 hex>",
    "size": 12345678,
    "requiresInfra": 1,
    "publishedUtc": "2026-10-24T12:00:00Z"
  },
  "web": {
    "version": "2026.10.24.77",
    "base": "https://dtsmailreleases.blob.core.windows.net/server/web/2026.10.24.77/",
    "minApi": "2026.10.24.512",
    "publishedUtc": "2026-10-24T12:05:00Z"
  }
}
```

- `api.requiresInfra`: the lowest infra version (see §5) this API build needs. Read by the pipeline from
  `selfhost/plugins/dts-mail/skills/setup/infra/INFRA_VERSION`.
- `web.minApi`: the API version Chuck's production ran when this web build was published (`GET /api/version` on
  `https://dts-email-ingest.azurewebsites.net`). A friend's server only offers this web build once its own API is at
  least that version.
- The Cloudflare Email Worker is not in the manifest: its script is embedded in the API package (§2.4).

Pipeline secrets: `SERVER_RELEASES_SAS` (write SAS for container `server`, without the leading `?`), in both the
backend and web pipelines. Uploads use `curl` Put Blob, like the desktop pipeline.

## 2. Backend (EmailIngest)

### 2.1 App settings (new or newly used by friends)

| Setting | Friend value | Purpose |
|---|---|---|
| `SETUP_KEY` | random 32 bytes, base64url | Enables `setup/*` (header `X-Setup-Key`). Unset → those routes answer 404. |
| `RELEASE_MANIFEST_URL` | `https://dtsmailreleases.blob.core.windows.net/server/stable/manifest.json` | Unset → no self-update (Chuck's prod) |
| `AUTO_UPDATE` | `true` | `false` keeps checking and reporting but never deploys |
| `DTS_INFRA_VERSION` | from `INFRA_VERSION` | what the friend's Bicep last deployed |
| `DTS_SUBSCRIPTION_ID`, `DTS_RESOURCE_GROUP` | from Bicep | for the ARM self-deploy (`WEBSITE_SITE_NAME` names the app) |
| `WEB_APP_URL` | `https://mail.<domain>` (or the SWA default host) | invite links |
| `CORS_ORIGINS` | web origins | also mirrored in the Function App's platform CORS |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_EMAIL_WORKER` (`dts-email-ingest`) | | existing |
| `SMTP_HOST` `smtp.mx.cloudflare.net`, `SMTP_PORT` `465`, `SMTP_USER` `api_token`, `SMTP_PASSWORD` = the Cloudflare token | | existing |
| `AI_ENDPOINT` `https://<acct>.services.ai.azure.com`, `AI_KEY`, `AI_DEPLOYMENT` `Decision-1`, `AI_MODEL_SMALL` `gpt-5.4-nano`, `AI_MODEL_LARGE` `gpt-5.4-mini` | only when AI is chosen | existing |
| `EmailStorage`, `AzureWebJobsStorage`, `DEPLOYMENT_STORAGE_CONNECTION_STRING`, `APPLICATIONINSIGHTS_CONNECTION_STRING`, `INGEST_KEY`, `JWT_SIGNING_KEY`, `MFA_ENCRYPTION_KEY` | Bicep / generated | existing |

### 2.2 Public endpoint

`GET /api/version` (anonymous):
```json
{ "version": "2026.10.24.512", "commit": "31a37a0", "infraVersion": 1,
  "web": { "version": "2026.10.24.77", "base": "https://…/server/web/2026.10.24.77/" },
  "update": { "enabled": true, "status": "current", "latest": "2026.10.24.512", "checkedUtc": "…" } }
```
`version` is `"dev"` for local builds. `web` is null until the updater has recorded a compatible web build.
`update.status`: `disabled | current | available | updating | needs-infra | failed` (`available` = a newer
release exists but `AUTO_UPDATE=false`).

### 2.3 Setup endpoints (`X-Setup-Key`, all JSON, 404 when `SETUP_KEY` is unset, 401 on a wrong key)

| Method / route | Body | Result |
|---|---|---|
| `GET setup/status` | | `{version, infraVersion, apiBase, webAppUrl, cloudflare:{configured, tokenOk, error?}, smtp:{configured}, ai:{configured}, worker:{name, embeddedHash, deployedHash}, domains:[{domain, enabled}], users:{count, admins:[email]}, update:{…as /version}}` |
| `POST setup/worker` | | deploys/refreshes the Email Worker; `{name, hash}` |
| `POST setup/admin` | `{email, displayName}` | First (or another) system admin, created with an invite instead of a password: `{userId, email, inviteCode, expiresUtc, acceptUrl}`; `acceptUrl` = `WEB_APP_URL/#invite?email=…&code=…`. An existing user with a pending invite gets a new code; an existing active user → 409. |
| `POST setup/domain` | `{domain, adminEmail?, replaceExistingMail?}` | Hosts the domain: runs the migration wizard's inspect + email switch as that admin (first admin when omitted). Zone must be active on the configured Cloudflare account (else 409 with the reason). If the domain's MX points at another mail provider and `replaceExistingMail` isn't true → 409 `{needsConfirmation:true, mailProvider, mxHosts}`. Also writes the discovery TXT (§4). Returns the migration state (`status`, `emailTestPassed`, `emailTest`, `log`). Takes up to ~3 minutes (round-trip test). |
| `POST setup/update` | | runs the updater now; returns the update state |

### 2.4a Large attachments

Files the user sends as download links go to the private `shared-files` container of the server's own storage
account (`EmailStorage`); nothing goes through Chuck's infrastructure. `GET files/uploads` → `{enabled, maxBytes,
linkDays}`; `POST files/uploads {fileName, contentType, size}` → `{fileName, uploadUrl, uploadExpiresUtc,
uploadHeaders, downloadUrl, expiresUtc}`. The client PUTs the file to `uploadUrl` (create/write SAS for that one blob,
2 hours) with `uploadHeaders`; `downloadUrl` is a read-only SAS valid **365 days** that forces a download under the
original name. The automatic links for messages over 10 MB use the same container and lifetime, and the daily
`PurgeSharedFiles` timer deletes blobs a day after their links expire. Browsers need blob-service CORS (PUT) for the
web origins (Bicep sets it).

### 2.4 Email Worker

`cloudflare-worker/worker.js` is embedded in the API assembly. Deployed with `PUT /accounts/{id}/workers/scripts/{name}`
(multipart: `metadata` = `{main_module:"worker.js", compatibility_date:"2025-01-01", bindings:[{type:"plain_text",
name:"INGEST_URL", text:"https://<host>/api/ingest"}, {type:"secret_text", name:"INGEST_KEY", text:<INGEST_KEY>}]}`,
part `worker.js` as `application/javascript+module`). Its hash (first 12 hex of SHA-256 of the script) is stored
after a deploy; the updater redeploys when the embedded hash differs.

### 2.5 Self-update (timer `SelfUpdate`, hourly at :17; also `setup/update`)

1. Disabled unless `RELEASE_MANIFEST_URL` is set. Fetch the manifest (no-cache), require `schema == 1`.
2. If `api.version` > running version: if `api.requiresInfra` > `DTS_INFRA_VERSION` → status `needs-infra` (the
   manage skill re-runs Bicep). Otherwise, unless `AUTO_UPDATE=false`: download the zip, check `size` and `sha256`,
   then `PUT https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{site}/extensions/onedeploy?api-version=2024-04-01`
   `{"properties":{"packageUri":"<api.url>","remoteBuild":false}}` with a managed-identity token. The app restarts on
   the new build. The same version is retried at most 3 times, 2 hours apart, then `failed` until a newer release.
3. Web: if `web.minApi` ≤ running version, record `web` (served by `/version`).
4. Worker: if Cloudflare is configured and the embedded worker hash ≠ deployed hash, redeploy it.
5. State lives in table `system`, PK `release`, RK `state`.

The Function App's system-assigned identity has **Website Contributor** on the Function App itself (Bicep).

## 3. Web client

- One build, published per version to `web/<version>/` with Vite `base` set to that absolute URL.
- `window.__DTS_CONFIG__ = { apiBaseUrl }` (set by the loader) overrides `DEFAULT_BASE_URL` in `core/src/transport.ts`.
- **Loader** (in the kit: `selfhost/plugins/dts-mail/skills/setup/web-loader/`, deployed once to the friend's Static Web
  App): `index.html` + `loader.js` + `config.json` (`{"apiBaseUrl":"https://<app>.azurewebsites.net/api"}`) +
  `staticwebapp.config.json` + icons/manifest. On load: read `config.json` → `GET {apiBaseUrl}/version` → take
  `web.base` → fetch `{base}index.html` → copy its stylesheet, modulepreload and module-script tags into the page.
  If the server is unreachable or has no web build yet, show a friendly message with a retry.

## 4. Server discovery

TXT record `_dtsmail.<domain>` = `v=dtsmail1 api=https://<app>.azurewebsites.net/api`. The desktop and web sign-in
screens look it up (DNS-over-HTTPS, `https://cloudflare-dns.com/dns-query?name=_dtsmail.<domain>&type=TXT`,
`accept: application/dns-json`) for the email address typed in, when the user hasn't chosen a server by hand; no
record → the built-in default. Shared code: `core/src/discovery.ts` → `discoverServer(email): Promise<string | null>`.

## 5. Infrastructure (Bicep, in the kit)

`selfhost/plugins/dts-mail/skills/setup/infra/`:
- `main.bicep`: storage account, Log Analytics + Application Insights, Flex Consumption plan (FC1) + Function App
  (.NET 8 isolated, system identity, platform CORS, all §2.1 settings), Website Contributor role on itself, blob CORS
  (PUT) and queue CORS for the web origins,
  `onedeploy` extension with the manifest's `api.url`, Static Web App (Free). Secrets come in as `@secure()` params.
  Outputs: `functionAppName`, `apiBaseUrl`, `staticWebAppName`, `staticWebAppHostname`, `storageAccountName`.
- `ai.bicep` (optional, separate deployment, always in the friend's own subscription): AI Services account +
  deployments `Decision-1` (Microsoft, `Microsoft-Decision-1` v1), `gpt-5.4-nano` and `gpt-5.4-mini` (OpenAI,
  `2026-03-17`). The deployment type is chosen per model by `scripts/Test-AiRegion.ps1` from what the region offers
  and has quota for (new Decision-1 deployments in eastus2 are DataZoneStandard only); the AI account may live in a
  different region from the server. Outputs `endpoint`, `accountName`.
- `INFRA_VERSION`: integer, read by Bicep (`loadTextContent`) into `DTS_INFRA_VERSION` and by the backend pipeline
  into `api.requiresInfra`. Bump it when a backend change needs new infrastructure or settings.

Re-running `main.bicep` must keep existing secrets: the manage skill reads the current app settings and passes them back.

## 6. Cloudflare

One account-owned API token, used for setup, the app's domain features and as the SMTP password. Friends need the
Workers Paid plan ($5/month, 3,000 emails included) to send to arbitrary recipients; receiving is free.
Exact permissions and click-by-click steps: `selfhost/plugins/dts-mail/skills/setup/references/cloudflare-token.md`.
Secrets are typed into a masked Windows dialog (`scripts/Read-Secret.ps1`), never into the chat.

## 7. Kit and its publication

`selfhost/` is the root of the public GitHub repo (a Claude Code marketplace):
`.claude-plugin/marketplace.json` → plugin `plugins/dts-mail` with skills `setup` (`/dts-mail:setup`) and `manage`
(`/dts-mail:manage`). The backend pipeline mirrors `selfhost/` to GitHub when it changes. Bump `version` in
`plugins/dts-mail/.claude-plugin/plugin.json` with every kit change, or friends won't receive it.
