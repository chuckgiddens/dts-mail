# How DTS Mail works (for the people running it)

```
 Someone emails you@yourdomain.com
        │
        ▼
 Cloudflare Email Routing ── catch-all rule ──▶ Worker "dts-email-ingest" ──▶ your Function App /api/ingest
                                                                                   │ junk check, filing
                                                                                   ▼
                                                                      Azure Storage (your mail, attachments)
                                                                                   │
 Desktop app / web app / iPhone app ◀── your Function App's API ◀───────────────────┘
        │
        └─ you send ─▶ Function App ─▶ Cloudflare Email Sending (SMTP relay) ─▶ the recipient
```

Everything that holds your mail is in **your** Azure subscription and **your** Cloudflare account. Chuck can't read
it and doesn't run any part of it; he publishes the software.

## The pieces

- **Function App** (`dtsmail…` in your resource group): the mail server and its API. Secrets (signing keys, the
  Cloudflare token) live in its app settings, in Azure.
- **Storage account**: mail, attachments, settings, and the per-device queues that tell your apps about new mail
  within seconds.
- **Static Web App** (`…-web`): the web version at `https://mail.yourdomain.com`. It's a tiny loader page; the app
  itself is downloaded from Chuck's release site, always the version that matches your server.
- **Cloudflare**: Email Routing (inbound), a small Worker that passes each message to your server, Email Sending
  (outbound), and DNS records: MX/SPF/DKIM/DMARC for mail, `_dtsmail.yourdomain.com` so the apps can find your
  server from your email address, and `mail.yourdomain.com` for the web app.
- **AI** (optional): an Azure AI Foundry resource with three models — Decision-1 for the junk filter, and two small
  GPT models for summaries, smart replies and writing help.

## Updates

- **Server**: every hour it checks Chuck's release channel. Chuck only publishes a release after it is running on his
  own server and has passed its health check. Your server downloads it, verifies its checksum, and installs it on
  itself (about a minute; mail that arrives meanwhile is retried by Cloudflare). If a release ever needs a change to
  your Azure resources, it waits and reports `needs-infra`; run `/dts-mail:manage` → re-apply infrastructure.
- **Web app**: always the build that matches your server — nothing to do.
- **Desktop app**: updates itself in the background from Chuck's release site.
- **This Claude Code plugin**: turn on auto-update for the `dts-mail` marketplace (`/plugin` → *Marketplaces*), or run
  `/plugin marketplace update dts-mail` now and then.

You can turn automatic server updates off (`/dts-mail:manage` → auto-update off); it then only reports that a new
release is available. Keep it on unless you have a reason: the desktop apps update themselves and expect a current
server.

## Security notes

- Two-step sign-in (authenticator app) is required for every account.
- The setup endpoints need a key (`SETUP_KEY`) that only exists in your Function App's settings; only someone who
  can sign in to your Azure subscription can read it.
- The server can redeploy itself and nothing else: its managed identity has *Website Contributor* on the Function App
  only.
- Releases are fetched over HTTPS from Chuck's storage account and checked against the published SHA-256 before
  install.
