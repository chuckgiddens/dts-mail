# Troubleshooting DTS Mail setup

Find the symptom, try the fix, and re-run the step (every step is safe to repeat).

## Computer and Azure CLI

| Symptom | Fix |
|---|---|
| `az` not found | `winget install -e --id Microsoft.AzureCLI`, open a new terminal (restart Claude Code), `az login`. |
| `Please run 'az login'` / expired token | Ask the user to run `az login` themselves, then continue. |
| A script is blocked by execution policy | Use the documented form: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<script>"`. |
| The token window never appears | It may be behind other windows (check the taskbar for "DTS Mail - Cloudflare"). Claude Code must be running on the same Windows desktop as the user, not over SSH or in a cloud session. |
| `npx` not found | Install Node.js LTS (`winget install -e --id OpenJS.NodeJS.LTS`), restart Claude Code, re-run `Deploy-WebLoader.ps1`. |

## Azure deployment (Deploy-Infra.ps1)

| Error contains | Meaning / fix |
|---|---|
| `MissingSubscriptionRegistration` / `not registered to use namespace` | `az provider register --namespace <namespace> --wait`, then re-run. |
| `LocationNotAvailableForResourceType` or Flex Consumption not offered | Re-run with `-Location eastus2`. |
| `AuthorizationFailed` on `Microsoft.Authorization/roleAssignments` | The signed-in user isn't an Owner of the subscription; an owner must run setup (or grant *User Access Administrator*). |
| `StorageAccountAlreadyTaken` / name not available | Rare name clash: delete the half-created resource group and re-run with a different `-ResourceGroup` name (names derive from it). |
| AI account name `already exists` (soft-deleted) | `az cognitiveservices account list-deleted`, then `az cognitiveservices account purge -g <rg> -n <name> -l <location>`. |
| onedeploy / `Deployment failed` on the `onedeploy` extension | Re-run Deploy-Infra once (first starts can time out). If it repeats, `Invoke-DtsSetup.ps1 -Action version` and the Function App's *Deployment Center* logs in the portal. |
| Wait-DtsServer times out | Portal → resource group → *Deployments* for a failed step; Function App → *Log stream*. |

## AI (your own Azure AI Foundry)

| Symptom | Fix |
|---|---|
| Test-AiRegion: model `not offered in this region` | Check several regions at once: `Test-AiRegion.ps1 -Location eastus2,swedencentral,westus3,eastus,northcentralus`. The AI account can be in a different region from the mail server. |
| Test-AiRegion: `quota left 0` / deployment fails with `InsufficientQuota` | New subscriptions often start with little or no model quota. Request more in Azure AI Foundry → *Management* → *Quota* (pick the model and deployment type shown), or lower the capacity (`-SmallModelCapacity 50` etc.). Meanwhile mail works without AI. |
| `junkDetection: false` in `/api/health` | The AI step was skipped (see Deploy-Infra's `WARN:`). `/dts-mail:manage` → add AI later. |
| AI calls fail with `401` | The key was regenerated in Azure. `Deploy-Infra.ps1` re-reads the current key and updates the server. |
| AI calls fail with `429` | Rate limited: raise the deployment's capacity in Azure AI Foundry → *Deployments* → *Edit*, quota permitting. |
| Junk filter errors mentioning `Content-Length` | Nothing to change on your side — the server already sends it; this only matters for people writing their own client for Decision-1. If you see it in the logs, tell Chuck. |
| Incoming mail all lands in Inbox, logs show `llm-error` | The junk filter couldn't reach Decision-1 (quota, 401, region outage). Mail is never lost — it goes to the Inbox. See the rows above, then **Check AI** in `/dts-mail:manage`. |

## Cloudflare

| Symptom | Fix |
|---|---|
| Set-CloudflareToken: token not accepted | Wrong value, expired, or created in another account. Create a new one (`cloudflare-token.md`). |
| A permission check FAILs | Edit the token in Cloudflare, add the named permission row, re-run with `-UseSaved`. |
| Zone not found / not active | Domain isn't in that account, or its nameservers aren't switched to Cloudflare yet (status must be *Active*). |
| setup/worker 403 | Token lacks *Workers Scripts: Edit*. |
| setup/domain 409 `needsConfirmation` | The domain receives mail elsewhere today. Confirm with the user before re-running with `-ReplaceExistingMail`. |
| setup/domain test email didn't arrive → records restored | The Worker isn't receiving: re-run `-Action worker`, then retry. Check Cloudflare → *Workers & Pages* → `dts-email-ingest` → *Logs*. |
| Sending fails with SMTP `535` / authentication | Token lacks *Email Sending: Edit*, or Workers Paid isn't active, or the domain's Email Sending onboarding isn't finished (Cloudflare → *Compute* → *Email Service* → *Email Sending*: domain should be listed). |
| Outside recipients don't get mail but your own addresses do | Workers Paid plan missing. |
| Mail lands in recipients' spam | Give the new DKIM/SPF/DMARC records a few hours; make sure there is only **one** SPF record at the domain root. |

## Web app and sign-in

| Symptom | Fix |
|---|---|
| Set-WebDomain stays `Validating`/`WAIT` | DNS can take a while: run it again in 10 minutes. The CNAME must be *DNS only* (grey cloud). |
| Web page says it can't reach the server | `Invoke-DtsSetup.ps1 -Action version` must show a `web` section; if not, `-Action update`. |
| Browser errors mentioning CORS | The web address isn't in the server's allowed origins: `Deploy-Infra.ps1 -CustomWebHost mail.<domain>` (re-applies CORS everywhere). |
| Invite link "expired or doesn't match" | Codes last 7 days and work once: `Invoke-DtsSetup.ps1 -Action admin -Email … -DisplayName …` issues a new one. |
| Desktop app can't find the server | Sign-in screen → **Server settings** → paste the API address (`apiBaseUrl` in `%LOCALAPPDATA%\DtsMail\setup.json`). |
| Lost phone / authenticator | Sign in with one of the recovery codes shown when two-step was set up. Otherwise another admin: desktop app → Settings → People → *Reset two-step verification*. The only admin with no codes: `/dts-mail:manage` → add another administrator (e.g. a second address of yours), sign in as them and reset your main account from Settings → People. |

## Updates

`Invoke-DtsSetup.ps1 -Action version` → `update.status`:
- `current`: nothing to do. `available`: auto-update is off. `updating`: wait a few minutes.
- `needs-infra`: `/dts-mail:manage` → re-apply infrastructure.
- `failed`: the same release failed to install 3 times. `/dts-mail:manage` → errors; then `-Action update` to retry.

## Large files sent as links

| Symptom | Cause and fix |
|---|---|
| The app never offers "Send as a download link" | The server is older than the feature (it updates within the hour), or the file is 4 MB or smaller. |
| Web app: "Couldn't reach your DTS Mail storage" | The storage account's blob CORS doesn't allow the web address. Re-apply the infrastructure (`/dts-mail:manage` → re-apply), which sets it for the web app's addresses. |
| "Your DTS Mail storage refused the upload (403)" | The two-hour upload link expired before the file finished uploading (a very slow connection). Try again. |
| A recipient's link says the file doesn't exist | The year is up and the file was deleted, or it was removed by hand from the `shared-files` container. Send it again. |
