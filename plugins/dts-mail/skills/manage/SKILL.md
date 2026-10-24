---
name: manage
description: Day-to-day care of a DTS Mail server set up with /dts-mail:setup — status, updates, re-applying infrastructure, adding a domain or admin, rotating the Cloudflare token, recent errors, auto-update on/off, and uninstalling. Use when the user asks about their DTS Mail server's health, updates, or configuration.
argument-hint: "[status | update | infra | add-ai | check-ai | add-domain | add-admin | rotate-token | errors | auto-update on|off | uninstall]"
disable-model-invocation: true
---

# Manage DTS Mail

Helping a friend of Chuck Giddens look after their own DTS Mail server. Plain language, confirm before changes, and
never take secrets or passwords in the chat (tokens go through the masked dialog; people set their own passwords).

Scripts live in the setup skill. Run them as
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/<Script>.ps1" <args>`.
References: `${CLAUDE_PLUGIN_ROOT}/skills/setup/references/` (`troubleshooting.md`, `costs.md`, `cloudflare-token.md`,
`how-it-works.md`).

## First: find the server

Run `Find-DtsServer.ps1` (pass `-ResourceGroup <name>` if it reports more than one). It works from any PC signed in
to the right subscription (`az account show`; switch with `az account set`). Then do what `$ARGUMENTS` asks, or ask
what they'd like to do.

## Status (default)

1. `Invoke-DtsSetup.ps1 -Action status` and `Invoke-DtsSetup.ps1 -Action version`.
2. Report briefly: running version and `update.status` (`current`, `available` = auto-update off, `updating`,
   `needs-infra` → offer **Re-apply infrastructure**, `failed` → offer **Update now** and check **Errors**);
   Cloudflare token OK; SMTP and AI configured; Worker deployed hash matches the embedded one (else offer
   `Invoke-DtsSetup.ps1 -Action worker`); hosted domains; number of users.
3. Cost question → `costs.md`; for actual spend point them to Azure portal → *Cost Management* for the resource group.

## Update now

`Invoke-DtsSetup.ps1 -Action update`. The server checks Chuck's release channel and installs a newer release itself
(it restarts; about a minute). Re-run `-Action version` after a couple of minutes to confirm. `needs-infra` → next
section. Desktop apps update themselves on their own schedule; the web app follows the server.

## Re-apply infrastructure

When `update.status` is `needs-infra`, or after the plugin itself was updated with infrastructure changes:
`Deploy-Infra.ps1` (it reads the current settings and keeps every secret, the web address and AI as they are; it also
installs the latest server release). Add `-WithAi` to turn AI on. Then `Wait-DtsServer.ps1` and **Status**.
If the plugin's web loader changed, also run `Deploy-WebLoader.ps1`.

## Add AI later

AI is always the friend's **own** Azure AI Foundry resource in their subscription. Explain what it adds (Decision-1:
smart junk filter on every incoming email; gpt-5.4-nano/mini: summaries, smart replies, writing help) and that it's
pay per use, typically cents to a few dollars a month. Then:
1. `az provider register --namespace Microsoft.CognitiveServices --wait`.
2. `Test-AiRegion.ps1 -Location <server region>`; if it fails, try several:
   `Test-AiRegion.ps1 -Location eastus2,swedencentral,westus3,eastus,northcentralus`. The AI account may be in a
   different region from the server. Quota 0 everywhere → they request quota in Azure AI Foundry (*Management* →
   *Quota*) and come back later.
3. `Deploy-Infra.ps1 -WithAi` (uses the region Test-AiRegion.ps1 saved; keeps everything else as it is).
4. **Check AI** below.

## Check AI

1. `Invoke-DtsSetup.ps1 -Action health` → `body.junkDetection: true` means the server has its AI settings.
2. The models: `az cognitiveservices account deployment list -g <rg> -n <aiAccountName> --query "[].{name:name, model:properties.model.name, type:sku.name, capacity:sku.capacity, state:properties.provisioningState}" -o table`
   (`aiAccountName`: `az cognitiveservices account list -g <rg> --query "[?tags.app=='dts-mail'].name" -o tsv`).
   Expect `Decision-1`, `gpt-5.4-nano`, `gpt-5.4-mini`, all `Succeeded`.
3. Recent AI errors: the **Errors** query below. `401` → the AI key was regenerated: run `Deploy-Infra.ps1`
   (it re-reads the current key from their AI account). `429` → rate limited: raise capacity in Azure AI Foundry →
   *Deployments* → the model → *Edit* (quota permitting).
4. Usage and quota for the region: `az cognitiveservices usage list -l <ai region> --query "[?contains(name.value,'Decision-1') || contains(name.value,'gpt-5.4-')].{name:name.value, used:currentValue, limit:limit}" -o table`.
   Cost so far: Azure portal → resource group → *Cost analysis*, filtered to the AI resource.

To turn AI off: `Deploy-Infra.ps1 -RemoveAi` (the server stops calling it), then optionally delete the AI resource.

## Add another domain

First explain what will change, exactly as setup step 9 point 0 does (the DNS changes table in
[GUIDE.md §6](https://github.com/chuckgiddens/dts-mail/blob/main/GUIDE.md#6-what-changes-in-your-domains-settings): MX to Cloudflare with the old records saved, merged SPF,
DKIM/`cf-bounce` added, DMARC only if missing, `_dtsmail` added, website and other records untouched; catch-all to
DTS Mail; existing forwarding rules keep working; old messages stay with the old provider; automatic undo if the test
fails). Afterwards, summarize what changed and mention **Settings → Domains → Undo email switch**.

The domain must be active in the **same** Cloudflare account, and the token must cover it (if the token is limited to
specific zones, edit it in Cloudflare to include the new one). Then
`Invoke-DtsSetup.ps1 -Action domain -Domain <new domain> -AdminEmail <an admin's email>` and handle a 409
`needsConfirmation` exactly as setup step 9 does: show `mailProvider`/`mxHosts`, explain that new mail for every
address at that domain moves to DTS Mail, and only pass `-ReplaceExistingMail` after an explicit yes.
Domains not yet on Cloudflare: the desktop app's **Settings → Domains → Migrate a domain** wizard moves them; walk
them through it with [GUIDE.md §5](https://github.com/chuckgiddens/dts-mail/blob/main/GUIDE.md#5-add-another-domain) (the only step outside the app is changing the
nameservers at their current provider).

## Add another administrator

`Invoke-DtsSetup.ps1 -Action admin -Email <email> -DisplayName "<name>"` → give them `body.acceptUrl` (7 days, works
once). Ordinary family members are better invited from the desktop app: **Settings → People**.

## Rotate the Cloudflare token

1. They create a new token with the same permissions (`cloudflare-token.md`). Get the account ID from
   `Find-DtsServer.ps1` output and the domain from **Status**.
2. `Set-CloudflareToken.ps1 -AccountId <id> -Domain <domain>` (masked dialog, full permission check).
3. `Deploy-Infra.ps1` pushes it to the server (also used as the SMTP password). Then **Status**.
4. They delete the old token in Cloudflare, and remove the local copy:
   `powershell.exe -NoProfile -Command "Remove-Item $env:LOCALAPPDATA\DtsMail\*.secret -ErrorAction SilentlyContinue"`.

## Errors

Last 24 hours from Application Insights (the extension installs itself on first use):
`az monitor app-insights query -g <rg> --app <functionAppName>-insights --analytics-query "union exceptions, (traces | where severityLevel >= 3) | where timestamp > ago(24h) | project timestamp, type, message=coalesce(outerMessage, message), operation_Name | order by timestamp desc | take 30" -o table`
(`<functionAppName>` is in `Find-DtsServer.ps1` output). Explain them in plain words and match against
`troubleshooting.md`. Never paste connection strings or keys from settings into the chat.

## Auto-update on/off

`Deploy-Infra.ps1 -AutoUpdate false` (or `true`). With it off, the server still checks hourly and reports
`available`; **Update now** won't install either — turn it back on to update. Recommend leaving it on: the desktop
apps update themselves and expect a current server.

## Uninstall

Only after the user explicitly confirms they want to delete their server **and all mail stored in it**. Suggest
exporting anything they need first (the desktop app can save messages).
1. `Remove-DtsCloudflare.ps1` (dry run: lists what it would remove) → confirm → `Remove-DtsCloudflare.ps1 -Yes`.
2. If they used AI: AI Services accounts are soft-deleted; after step 3 run
   `az cognitiveservices account purge -g <rg> -n <aiAccountName> -l <ai location>` so the name can be reused.
3. `az group delete -n <rg> --yes` (takes a few minutes; ask once more right before running it).
4. Remind them: incoming mail for the domain now has nowhere to go. In Cloudflare, point the MX records at their new
   provider or turn off Email Routing; cancel Workers Paid if nothing else uses it.
5. Remove the local state: `powershell.exe -NoProfile -Command "Remove-Item $env:LOCALAPPDATA\DtsMail -Recurse -ErrorAction SilentlyContinue"`.
