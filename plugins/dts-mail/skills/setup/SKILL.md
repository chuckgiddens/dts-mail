---
name: setup
description: Sets up a private DTS Mail email server in the user's own Azure subscription and Cloudflare account, step by step, resuming where a previous run stopped. Use when the user wants to install, set up, or finish setting up DTS Mail.
argument-hint: "[resource-group]"
disable-model-invocation: true
---

# Set up DTS Mail

You are walking a friend of Chuck Giddens through setting up their own DTS Mail server. They may not be a developer.
Be warm and plain-spoken, explain what each step does and roughly how long it takes, and confirm before anything that
costs money or changes their existing email.

What gets built (details: `${CLAUDE_SKILL_DIR}/references/how-it-works.md`):
- **Azure** (their subscription, one resource group, default `dtsmail`): a Function App (the mail server), storage,
  monitoring, a Static Web App (the web version of the app), and optionally AI models.
- **Cloudflare** (their account, domain already on Cloudflare): Email Routing delivers incoming mail to a small Worker
  that hands it to the server; Email Sending relays outgoing mail; DNS records for mail, discovery and `mail.<domain>`.
- The server **updates itself** from Chuck's releases; the desktop app updates itself too.

Costs (say this before creating anything; details in `${CLAUDE_SKILL_DIR}/references/costs.md`): Azure is
pay-as-you-go, typically **a few dollars a month** for a household; the Static Web App is free; Cloudflare's
**Workers Paid plan ($5/month)** is needed to send mail to anyone outside their own verified addresses; optional AI
adds cents to a few dollars a month.

## Ground rules

- **Never ask for or accept secrets in the chat.** The Cloudflare token is typed into a masked Windows dialog opened
  by `Set-CloudflareToken.ps1`. If the user pastes a token into the chat anyway, tell them to delete that token in
  Cloudflare and create a new one, and don't use it.
- **Never handle passwords.** The admin sets their own password and authenticator app from the invite link.
- **Run scripts like this** (works from both the PowerShell tool and Git Bash; quote the path, it may contain spaces):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/scripts/<Script>.ps1" <args>`
  Scripts print `OK:`, `WARN:`, `WAIT:` or `FAIL:` lines. Read them; on `FAIL` stop and fix before going on
  (`${CLAUDE_SKILL_DIR}/references/troubleshooting.md`).
- **Long steps**: Deploy-Infra (3-8 min), setup/domain (up to 3 min), Set-WebDomain (up to 15 min). Run them with a
  generous timeout (10+ minutes) and tell the user what's happening while they wait.
- **Resume, don't restart.** Answers and results are saved (no secrets) in `%LOCALAPPDATA%\DtsMail\setup.json`.
  Re-running a step is safe: every script and endpoint checks what already exists.

## Step 0 — Where are we?

1. Read the saved state: `powershell.exe -NoProfile -Command "if (Test-Path $env:LOCALAPPDATA\DtsMail\setup.json) { Get-Content $env:LOCALAPPDATA\DtsMail\setup.json } else { 'none' }"`
2. If it has a `resourceGroup` (or the user passed one as `$ARGUMENTS`), run
   `Invoke-DtsSetup.ps1 -Action status` and skip every step below that is already done:
   server answers → steps 1-6 done; `worker.deployedHash` set → step 7 done; `users.admins` non-empty → step 8 done;
   the domain in `domains` → step 9 done; `webLoaderDeployedUtc` in state → step 11 done; `webDomainReady` → step 12 done.
   Tell the user where you're picking up.
3. Otherwise start at step 1 with a two-line overview of what's ahead and the cost note above.

## Step 1 — Check the computer

Run each and fix what's missing (ask before installing anything):
- Windows: `powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString(); [Environment]::OSVersion.VersionString"`.
  This kit is written for Windows (the secret dialog is a Windows window). On macOS/Linux, stop and say so.
- Azure CLI ≥ 2.60: `az version -o json` (look at `"azure-cli"`). Missing or older → offer
  `winget install -e --id Microsoft.AzureCLI` (then a new terminal and `az login`).
- Signed in: `az account show --query "{name:name, id:id, user:user.name}" -o json`. Not signed in → ask the user to
  run `az login` in a terminal themselves, then continue.
- Subscription: `az account list --query "[].{name:name, id:id, isDefault:isDefault}" -o table`. More than one →
  ask which (AskUserQuestion), then `az account set --subscription <id>`.
- Owner rights (needed to let the server update itself):
  `az role assignment list --assignee "$(az account show --query user.name -o tsv)" --include-inherited --scope "/subscriptions/$(az account show --query id -o tsv)" --query "[].roleDefinitionName" -o tsv`.
  Needs `Owner` (or `User Access Administrator` + `Contributor`). Without it, stop: they need an owner to run setup.
- Node.js ≥ 18 (only for publishing the web app): `node --version`. Missing → ask, then
  `winget install -e --id OpenJS.NodeJS.LTS`; it's usable after a new terminal (Claude Code may need restarting —
  you can continue with other steps and come back for step 11).
- Resource providers (each takes a minute the first time):
  `az provider register --namespace Microsoft.Web --wait`, and the same for `Microsoft.Storage`,
  `Microsoft.OperationalInsights`, `Microsoft.Insights`, plus `Microsoft.CognitiveServices` if they'll want AI.

## Step 2 — A few questions

Ask (use AskUserQuestion for the choices; free text in chat for names):
- **Domain** already on Cloudflare (e.g. `example.com`). It must show as *Active* in their Cloudflare dashboard.
- **Their email address** on that domain (becomes the admin's sign-in, e.g. `bob@example.com`) and **display name**.
- **Region**: `eastus2` (recommended), `centralus`, `westus2`, `westeurope`. The Static Web App uses the same
  region if allowed (`centralus`, `eastus2`, `westus2`, `westeurope`, `eastasia`), else `eastus2`.
- **Web address**: `mail.<domain>` (recommended) or none (they'll use the Azure-provided address).
- **AI features** — ask with AskUserQuestion, options in this order:
  1. **"Yes, set up my own AI (Recommended)"** — creates *their own* Azure AI Foundry resource in their subscription
     (nobody else's, and never shared) with three models: **Decision-1** powers the smart junk filter (every incoming
     email is checked once); **gpt-5.4-nano** and **gpt-5.4-mini** power summaries, smart replies and writing help.
     Pay per use, typically cents to a few dollars a month for a household.
  2. **"No AI"** — everything else works; junk filtering then relies on their blocked/safe sender lists, and the AI
     buttons stay hidden. They can add AI later with `/dts-mail:manage`.
- **Resource group** name: default `dtsmail`.
- **Existing email on the domain?** Ask if they currently receive mail at that domain elsewhere (Google, Microsoft,
  another host). Setup will move it to DTS Mail; old messages stay at the old provider. Confirm they understand.

## Step 3 — Cloudflare plan and token

1. Sending: confirm they have, or will add, **Workers Paid** ($5/month) — dashboard → *Workers & Pages* → *Plans*.
   Without it, receiving works but replies to outside addresses fail. Let them choose to continue without it for now.
2. Walk them through creating the API token using `${CLAUDE_SKILL_DIR}/references/cloudflare-token.md` — give the
   steps one screen at a time, with the exact permission rows. Ask them to copy their **Account ID** (not secret;
   they can paste it in chat) from the domain's *Overview* page → *API* section.
3. Run `Set-CloudflareToken.ps1 -AccountId <id> -Domain <domain>`. A dialog titled *DTS Mail - Cloudflare* opens
   (tell them; it may be behind other windows): they paste the token and press OK. The script checks every
   permission and prints a table. `FAIL` → tell them which permission row to fix. If they edit the existing token's
   permissions in Cloudflare, re-check it with `-UseSaved` (no dialog); if they create a new token, run it again
   without `-UseSaved`. Nothing is saved until every required check passes.

## Step 4 — Build the Azure side

**If they chose AI**, first check their subscription can host the models:
`Test-AiRegion.ps1 -Location <region>` (the server region from step 2). It lists, per model, whether it's offered
in that region, the deployment type it will use (Global Standard, or Data Zone Standard where that's all that's
offered — common for Decision-1) and the free quota. On `FAIL`, try a few regions at once and keep the first that
fits — the AI account may live in a different region from the mail server:
`Test-AiRegion.ps1 -Location eastus2,swedencentral,westus3,eastus,northcentralus`.
If no region fits because quota is 0, explain they can request quota in Azure AI Foundry (*Management* → *Quota*,
usually approved quickly) or carry on without AI now and add it later with `/dts-mail:manage`. Capacities default to
50 (Decision-1) and 100 each (nano, mini, in thousands of tokens per minute) — plenty for a household; pass
`-DecisionCapacity`/`-SmallModelCapacity`/`-LargeModelCapacity` to Test-AiRegion.ps1 to change them.

Run `Deploy-Infra.ps1 -ResourceGroup <rg> -Location <region> -StaticWebAppLocation <swa-region> -CustomWebHost mail.<domain>`
(omit `-CustomWebHost` if they chose none; add `-WithAi` if they chose AI — it uses the region Test-AiRegion.ps1
saved, or pass `-AiLocation <region>`). It creates the resource group, generates the server's secrets, deploys
**their own** AI Foundry resource and models first if asked (continuing without AI on region/quota errors — tell the
user if that happened), then everything else from `infra/main.bicep` — including the AI settings `AI_ENDPOINT`
(`https://<their account>.services.ai.azure.com`), `AI_KEY` (read with `az cognitiveservices account keys list`
inside the script, never shown), `AI_DEPLOYMENT=Decision-1`, `AI_MODEL_SMALL=gpt-5.4-nano`,
`AI_MODEL_LARGE=gpt-5.4-mini` — and installs the latest server release.
Success prints `OK: deployment finished.` and the server's names and addresses (no secrets).

Common failures: region doesn't offer Flex Consumption → re-run with `-Location eastus2`; a provider not registered
→ step 1; `AuthorizationFailed` on the role assignment → not Owner (step 1).

## Step 5 — Wait for the server

`Wait-DtsServer.ps1` (up to 10 minutes). It prints the running version when ready.

## Step 6 — Server self-check

`Invoke-DtsSetup.ps1 -Action status`. Expect `cloudflare.tokenOk: true` and `smtp.configured: true`. If
`cloudflare.tokenOk` is false, show `cloudflare.error` and go back to step 3.
If they chose AI: `Invoke-DtsSetup.ps1 -Action health` must show `body.junkDetection: true`. False means the AI
step was skipped — say why (Deploy-Infra printed a `WARN:`), and offer `/dts-mail:manage` → add AI later.

## Step 7 — Inbound mail Worker

`Invoke-DtsSetup.ps1 -Action worker` deploys the small Cloudflare Worker that receives mail. Expect `ok: true` with
`body.name` = `dts-email-ingest`. A 403 from Cloudflare means the token lacks *Workers Scripts: Edit*.

## Step 8 — The administrator account

`Invoke-DtsSetup.ps1 -Action admin -Email <their email> -DisplayName "<name>"`. Keep `body.acceptUrl` and
`body.inviteCode` for step 13 (don't show them yet). A 409 means the account already exists and is active: skip.

## Step 9 — Move the domain's email to DTS Mail

0. **Before running anything**, explain in plain words what will change in the domain's DNS, using
   the table in [GUIDE.md §6](https://github.com/chuckgiddens/dts-mail/blob/main/GUIDE.md#6-what-changes-in-your-domains-settings):
   MX moves to Cloudflare (old MX and SPF saved first), one merged SPF record, DKIM and `cf-bounce` records added,
   DMARC added only if missing (monitor-only), `_dtsmail` and (first domain) `mail.` added; **website and all other
   records untouched**. Also: a catch-all rule sends every address to DTS Mail, existing Cloudflare forwarding rules
   for specific addresses keep forwarding, old messages stay with the old provider (they can import them later),
   and a failed test puts everything back automatically. Keep it short; offer the guide link for the details.
1. `Invoke-DtsSetup.ps1 -Action domain -Domain <domain> -AdminEmail <their email>`.
2. If it answers 409 with `body.needsConfirmation: true`: the domain currently receives mail at
   `body.mailProvider` (`body.mxHosts`). Explain plainly that continuing makes new mail for **every** address at the
   domain go to DTS Mail instead, that old mail stays at the old provider, and that the previous records are backed up
   and restored automatically if the test fails. Ask with AskUserQuestion (Replace / Stop). Only on an explicit
   "Replace", run again with `-ReplaceExistingMail`.
3. Other 409s: the zone isn't active on that Cloudflare account, or the token can't see it — fix and retry.
4. It runs a round-trip test (up to ~2.5 minutes). `body.emailTestPassed: true` → sending and receiving both work.
   False → read `body.emailTest`: usually outgoing mail isn't enabled yet (Workers Paid, or Email Sending still being
   activated by Cloudflare for the domain — can take up to an hour). Receiving still works; they can test later by
   sending themselves a message from another account.
5. Tell them, in two or three lines, what was actually changed (from `body.log`), and that **Settings → Domains →
   Undo email switch** in the desktop app restores the previous email records at any time.

## Step 10 — Pick up the matching web app

`Invoke-DtsSetup.ps1 -Action update` (records the web app build that matches this server; `body` shows the update
state). Then `Invoke-DtsSetup.ps1 -Action version` should show a non-null `body.web`.

## Step 11 — Publish the web app

`Deploy-WebLoader.ps1` (needs Node.js from step 1). Prints the Azure address it answers on.

## Step 12 — Its own address

If they chose `mail.<domain>`: `Set-WebDomain.ps1 -HostName mail.<domain>`. It adds a DNS-only CNAME in Cloudflare and
waits for Azure to validate it and issue a certificate (usually 2-10 minutes; `WAIT:` means run it again later —
you can carry on and come back).

## Step 13 — Apps and first sign-in

1. Offer the desktop app for Windows (ask first; ~100 MB download): `Install-Desktop.ps1` downloads it, checks the
   digital signature, and opens the installer. The app updates itself afterwards.
2. Give them their invite link from step 8 — if the custom address isn't ready yet, swap the host for the Static Web
   App address in `setup.json` (`staticWebAppHostname`). Explain: open it in a browser, choose a password, then scan
   the QR code with an authenticator app (Microsoft Authenticator, Google Authenticator, 1Password…). Two-step sign-in
   is required for everyone. The code works once and expires in 7 days (re-run step 8 for a new one).
3. Desktop app sign-in: they type their email address and the app finds their server automatically (the `_dtsmail`
   DNS record). If it doesn't, click **Server settings** on the sign-in screen and paste `apiBaseUrl` from setup.json.
   They can accept the invite there too (email + invite code).
4. iPhone: the iOS app is distributed by Chuck through TestFlight — they should ask him for an invite. On first
   launch, **Server settings** → `apiBaseUrl`, then sign in (or scan the QR from *Settings → Account → Sign in on
   your phone* on the desktop).

## Step 14 — Wrap up

Summarize in a few lines:
- Web address, the server's API address, the resource group, and that AI is on/off.
- **Updates are automatic**: the server checks Chuck's releases every hour and installs them; the web app always
  matches the server; the desktop app updates itself. If an update ever needs infrastructure changes, the apps' admin
  status (or `/dts-mail:manage`) will say so.
- **Their guide for what comes next**: https://github.com/chuckgiddens/dts-mail/blob/main/GUIDE.md — first sign-in, adding family, bringing old email across (Settings →
  Import mail), adding another domain and exactly what that changes, and undoing a switch. Give them this link.
- Family and friends: desktop app → **Settings → People** → invite them (they get mailboxes on the domain).
- Day-to-day tasks (status, add a domain, rotate the token, see errors, uninstall): `/dts-mail:manage`.
- The Cloudflare token kept locally during setup can now be removed: run
  `powershell.exe -NoProfile -Command "Remove-Item $env:LOCALAPPDATA\DtsMail\*.secret -ErrorAction SilentlyContinue"`
  (the server keeps its own copy in Azure).
