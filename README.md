# DTS Mail — your own email, set up for you by Claude

DTS Mail is the email service Chuck Giddens built and uses every day. It has a desktop app for Windows and Mac, a
web version you can open in any browser, and an iPhone app. It filters junk for you, can help you write emails with
AI, and handles email for your whole family on your own domain (like `you@yourname.com`).

This page lets you run **your own private copy**. Your email lives in **your** accounts, not Chuck's, and nobody else
can read it. You don't need to be technical: **Claude does the setup with you**, one step at a time, and explains
each step as it goes. Afterwards it **updates itself** whenever Chuck adds new features.

---

## Before you start: what you need

| You need | What it is | How to get it |
|---|---|---|
| **A Windows PC** | Setup runs on Windows. (Once it's done, you can read your mail on a Mac, iPhone or any browser too.) | — |
| **Claude Code** | The Claude app that does the setup with you. | Download it from [claude.com/claude-code](https://claude.com/claude-code) and sign in. |
| **Your own domain** | The part after the @ in your email address, e.g. `yourname.com`. | If you don't have one, you can buy one at [Cloudflare](https://dash.cloudflare.com) (about $10–15 a year). |
| **A Cloudflare account** with your domain on it | Cloudflare receives and sends your email. | Sign up free at [cloudflare.com](https://dash.cloudflare.com/sign-up). If your domain is somewhere else, choose **Add a domain** and follow Cloudflare's steps; it's ready when Cloudflare shows the domain as **Active**. |
| **A Microsoft Azure account** | Azure is where your email server runs. | Sign up at [azure.microsoft.com](https://azure.microsoft.com/free). It asks for a credit card; you only pay for what you use (see costs below). |
| **The Azure command-line tool** | Lets Claude set things up in your Azure account for you. | Download and install it from [aka.ms/installazurecliwindows](https://aka.ms/installazurecliwindows). |
| **About 45 minutes** | Most of it is waiting while Azure builds things. | — |

**Last step before you begin:** open **Windows PowerShell** (search for it in the Start menu), type `az login` and
press Enter. A browser window opens. Sign in with your Azure account, then close the browser and come back.

Don't worry about anything else. If Claude needs another tool, it asks before installing it.

---

## What it costs

You pay Azure and Cloudflare directly. Chuck doesn't charge anything.

| | Typical cost | Why |
|---|---|---|
| **Cloudflare Workers Paid plan** | **$5 a month** | Needed to *send* email to anyone outside your own accounts. Includes 3,000 emails a month. Receiving email is free. |
| **Azure** | **A few dollars a month** | Your server only runs when there's email to handle, plus storage for your mail and any large files you send as links. The web version is hosted free. |
| **AI features** (optional) | **Cents to a few dollars a month** | Junk filtering and writing help, charged only when used. Runs in your own Azure account. |

Most households pay about **$5–8 a month** in total. More detail: [costs](plugins/dts-mail/skills/setup/references/costs.md).

---

## Set it up

**1. Open Claude Code** and start a new session.

**2. Add DTS Mail to Claude.** Type these two lines into Claude, one at a time, pressing Enter after each:

```
/plugin marketplace add chuckgiddens/dts-mail
```

```
/plugin install dts-mail@dts-mail
```

**3. Start the setup.** Type:

```
/dts-mail:setup
```

Claude takes it from there. It will:

- check your PC has what it needs
- ask you a few simple questions: your domain, your name, and whether you'd like the AI features
- walk you, click by click, through creating a key in Cloudflare, so it can set up your email
- build your email server in Azure
- switch your domain's email over to DTS Mail (if your domain already gets email somewhere else, Claude stops and
  asks you first)
- put your web version at `https://mail.yourdomain.com`
- offer to install the desktop app for you
- give you a link to create your password

**If anything stops halfway** (your PC sleeps, you close Claude, something times out), just type `/dts-mail:setup`
again. It picks up where it left off.

### Your passwords stay private

You never type a password or key into the chat with Claude. The Cloudflare key goes into a small pop-up window on your
PC, and you choose your own email password yourself, in the app.

---

## After setup

**Read the [guide for what comes next](GUIDE.md)**: your first sign-in, adding family, bringing your old email across,
adding another domain and exactly what changes in your domain's settings when you do, and how large files are sent.

- **Signing in:** in the desktop app, the web version or the iPhone app, just enter your email address and password.
  The app finds your server by itself.
- **Adding family members:** open the desktop app → **Settings** → **People** → invite them. Each person gets an
  invite code (DTS Mail can email it to them) and chooses their own password.
- **The iPhone app:** ask Chuck for an invitation to the test version (Apple's TestFlight).
- **Updates:** nothing to do. Your server installs new versions by itself, the web version always matches it, and
  the desktop app updates itself.
- **Turn on updates for the setup tools too** (recommended): in Claude, type `/plugin`, choose **Marketplaces** →
  **dts-mail** → **Enable auto-update**.

## Need help later?

Type `/dts-mail:manage` in Claude Code. It can show whether everything is working, install an update right now, add
another domain, turn the AI features on or off, replace your Cloudflare key, show recent errors, or remove DTS Mail
completely.

Common questions:

- **Is my email private?** Yes. Your mail, and any large files you send as download links, are stored in your own
  Azure account. Nothing goes through Chuck's servers, and he can't see it.
- **What if I stop paying?** Your server stops and your email stops arriving. Use `/dts-mail:manage` → *uninstall*
  first if you're leaving, and move your domain's email somewhere else.
- **Do I need to keep my PC on?** No. Once setup is done, everything runs in the cloud.
- **Something went wrong.** See [troubleshooting](plugins/dts-mail/skills/setup/references/troubleshooting.md), or
  run `/dts-mail:manage` and ask Claude to check what's wrong.

Curious how it works? [How it fits together](plugins/dts-mail/skills/setup/references/how-it-works.md).
