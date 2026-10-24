# DTS Mail — your own email server, set up by Claude

DTS Mail is the email service Chuck Giddens built and uses every day: a fast desktop app for Windows and Mac, a web
version, and an iPhone app, with two-step sign-in, smart junk filtering, AI writing help (optional), aliases, and
mail for as many people and domains as you like.

This repository lets you run **your own copy** — on **your** Azure subscription and **your** Cloudflare account, so
your mail is yours alone. Claude Code does the setup with you, step by step, and afterwards your server **keeps
itself up to date** with Chuck's new features.

## What you need

- A **Windows** PC with [Claude Code](https://claude.com/claude-code) (the app or the CLI).
- An **Azure subscription** where you're an Owner, and the [Azure CLI](https://aka.ms/installazurecliwindows)
  signed in: run `az login` in a terminal.
- A **Cloudflare** account with your domain on it (status *Active*).
- About **45 minutes** the first time, mostly waiting for Azure.

Setup offers to install anything else it needs (Node.js, for publishing the web app).

## What it costs

You pay Azure and Cloudflare directly; there's no charge from Chuck.

- **Cloudflare Workers Paid: $5/month.** Needed to *send* mail to the outside world (3,000 emails a month included).
  Receiving is free.
- **Azure: usually a few dollars a month** for a household — the server runs only when there's work to do
  (Flex Consumption), plus storage for your mail and some logging. The web app's hosting is free.
- **AI features (optional):** pay per use, typically cents to a few dollars a month.

Most households land around **$5–8 a month** in total. Details:
[costs](plugins/dts-mail/skills/setup/references/costs.md).

## Install

In Claude Code, run:

```
/plugin marketplace add chuckgiddens/dts-mail
/plugin install dts-mail@dts-mail
```

Then turn on updates for the setup tools themselves: `/plugin` → **Marketplaces** → **dts-mail** →
**Enable auto-update**. (Or run `/plugin marketplace update dts-mail` from time to time.)

## Set up

```
/dts-mail:setup
```

Claude checks your PC, asks a few questions (your domain, your name, where in the world to run it, whether you want
AI), shows you how to create a Cloudflare API token, builds everything in Azure, moves your domain's email over
(only after you confirm, if it currently gets mail somewhere else), publishes your web app at
`https://mail.<your domain>`, and gives you your sign-in link. If anything stops halfway, run it again: it picks up
where it left off.

You'll never paste passwords or tokens into the chat: the Cloudflare token goes into a small Windows dialog, and you
choose your own password in the app.

## Afterwards

- **Updates are automatic**: your server installs Chuck's releases on its own (he only publishes what's already
  running on his server), the web app always matches it, and the desktop app updates itself.
- **Invite family and friends**: desktop app → *Settings* → *People*.
- **Everything else** — status, updating now, adding a domain, replacing the Cloudflare token, recent errors,
  uninstalling: `/dts-mail:manage`.

How it fits together: [how it works](plugins/dts-mail/skills/setup/references/how-it-works.md) ·
Problems: [troubleshooting](plugins/dts-mail/skills/setup/references/troubleshooting.md)
