# Using DTS Mail after setup

Your DTS Mail server is running. This guide covers what to do next: signing in, adding your family, bringing your old
email across, and adding another domain, including **exactly what changes in your domain's settings** when you do.

- [1. Your first sign-in](#1-your-first-sign-in)
- [2. Add family members](#2-add-family-members)
- [3. Addresses, catch-all and aliases](#3-addresses-catch-all-and-aliases)
- [4. Bring your old email across](#4-bring-your-old-email-across)
- [5. Add another domain](#5-add-another-domain)
- [6. What changes in your domain's settings](#6-what-changes-in-your-domains-settings)
- [7. Undoing a domain switch](#7-undoing-a-domain-switch)
- [8. Updates and getting help](#8-updates-and-getting-help)

---

## 1. Your first sign-in

At the end of setup, Claude gave you an **invite link** (it works once, for 7 days).

1. Open the link. It goes to your web version (`https://mail.yourdomain.com`).
2. Choose a password (at least 8 characters).
3. Set up **two-step sign-in**: scan the QR code with an authenticator app on your phone (Microsoft Authenticator,
   Google Authenticator, 1Password and so on), then type the 6-digit code it shows.
4. Save the **recovery codes** it shows you somewhere safe (a password manager, or printed). Each one gets you in once
   if you lose your phone.

From then on, sign in anywhere with your email address and password:

| Where | How |
|---|---|
| **Desktop app** (Windows, Mac) | Setup offered to install it. Otherwise download it from [the Windows installer](https://dtsmailreleases.blob.core.windows.net/desktop/DTS-Mail-Setup-x64.exe) or [the Mac version](https://dtsmailreleases.blob.core.windows.net/desktop/DTS-Mail-mac.dmg). It updates itself. |
| **Web** | `https://mail.yourdomain.com` in any browser. |
| **iPhone** | Ask Chuck for a TestFlight invitation. Or, on a computer that's signed in: **Settings → Account → Sign in on your phone** and scan the QR code. |

You don't need to tell the apps where your server is: they find it from your email address.

---

## 2. Add family members

1. Desktop app → **Settings** → **People** → invite someone.
2. Give them an address on your domain (e.g. `alex@yourdomain.com`). They can sign in with that address, or with an
   address they already have elsewhere.
3. DTS Mail gives them an **invite code**, and can email it to them. They open the app, choose **I have an invite
   code**, enter it, choose their own password and set up their authenticator app, the same as you did.

Invite codes last 7 days. If one expires, invite them again from **Settings → People**.

You can make someone an administrator of a domain so they can add people to it too.

---

## 3. Addresses, catch-all and aliases

- **Catch-all:** when your domain was set up, **you** became its catch-all. Email sent to any address at your domain
  that doesn't belong to someone (`shop@`, `info@`, a typo) arrives in your inbox. Nothing bounces.
- **Addresses:** each person can have several (**Settings → People**). Mail to an address goes only to its owner.
- **Aliases:** an address that forwards to one or more other mailboxes, including outside ones like a Gmail account
  (**Settings → Aliases**). Outside destinations get a one-time confirmation email from Cloudflare first.

---

## 4. Bring your old email across

Switching your domain to DTS Mail changes where **new** email goes. Your **old** messages stay with your previous
email provider until you move them:

1. Export your old mailbox as **.mbox** files. Gmail: [Google Takeout](https://takeout.google.com) → choose only
   *Mail*. Outlook / Microsoft 365: use the Outlook desktop app, or ask Claude for the current steps. Apple Mail:
   *Mailbox → Export Mailbox*.
2. Desktop app → **Settings** → **Import mail** → choose the .mbox files (or the folder holding them). Each file
   becomes a folder named after it; *Inbox*, *Sent*, *Junk*, *Trash* and *Archive* go into the matching DTS Mail
   folders. Gmail's export is one big file, so it arrives as one folder you can sort afterwards. Messages keep their
   original dates, and importing the same file twice doesn't create duplicates.

Keep your old account for a few weeks after switching, in case anyone was slow to update an address book.

---

## 5. Add another domain

There are two cases, depending on where the domain's settings (its DNS) are today.

### The domain is already in your Cloudflare account (status *Active*)

Easiest: in Claude Code, run `/dts-mail:manage` and ask to **add a domain**. Claude:

1. checks that your Cloudflare key is allowed to change that domain (if you limited the key to certain domains when you
   created it, Claude shows you how to add this one)
2. looks at where the domain's email goes today and, **if it already receives email somewhere else, stops and asks
   you** before changing anything
3. switches the domain's email to DTS Mail (the changes are in [section 6](#6-what-changes-in-your-domains-settings)),
   sends a test email to make sure it arrives, and puts everything back automatically if it doesn't
4. makes you the catch-all for the new domain and gives you an address there

You can do the same in the desktop app: **Settings → Domains → Migrate a domain**, type the domain, choose **Look up**.
It sees that the domain is already on Cloudflare and goes straight to **Switch email**.

### The domain is somewhere else (GoDaddy, Namecheap, Google Domains, and so on)

Use the desktop app's wizard, which moves the domain's settings into your Cloudflare account first:

1. **Settings → Domains → Migrate a domain**, type the domain, choose **Look up**. It shows where the domain is
   today and where its email goes.
2. **Records:** it gathers all of the domain's settings (website, email, verification records). If it can't read them
   all by itself, it asks you for an export file from your current provider, or a screenshot or copy-paste of their
   DNS page (reading those needs the AI features).
3. **Copy to Cloudflare** and **Verify**: the settings are created in your Cloudflare account and checked against the
   live ones. Your website and email keep working; nothing has switched yet.
4. **Change nameservers:** the wizard shows two Cloudflare nameservers and step-by-step instructions for your
   provider. You log in at your provider and replace the nameservers. This is the only step you do outside DTS Mail.
   Choose **Check now** in the wizard afterwards. Cloudflare usually takes over within minutes, sometimes a few hours.
5. **Switch email:** the same email switch as above, with the test email and the automatic undo.
6. **Monitoring:** for the next 72 hours the wizard keeps checking that your website and email still answer, and tells
   you if anything changed.

**Before you switch a domain that already receives email**, tell the people who use it, and remember that their old
messages stay with the old provider (see [section 4](#4-bring-your-old-email-across)).

---

## 6. What changes in your domain's settings

These are the changes made to a domain's DNS records in Cloudflare when its email switches to DTS Mail.
**Your website and every other record are left exactly as they were.**

| Record | Before | After | Why |
|---|---|---|---|
| **MX** on `yourdomain.com` | Your old email provider (e.g. Google, Microsoft) | Cloudflare's three email servers (`route1/2/3.mx.cloudflare.net`) | This is the switch itself: new email now goes to Cloudflare, which hands it to your DTS Mail server. The old MX records are **saved** first so they can be put back. |
| **SPF** (TXT on `yourdomain.com`, starts `v=spf1`) | Your existing one, if any | **One** merged SPF record: Cloudflare's entry added, your old email provider's entry removed, anything else (e.g. a newsletter service) **kept** | Tells the world which servers may send email as your domain. The old record is **saved** first. |
| **DKIM** (TXT, `…._domainkey.yourdomain.com`) | — | Added | Cloudflare signs your email so receivers can trust it. |
| **`cf-bounce.yourdomain.com`** (MX + TXT) | — | Added | Lets Cloudflare send your outgoing email and handle bounces. |
| **DMARC** (TXT on `_dmarc.yourdomain.com`) | Your existing one, if any | **Unchanged** if you had one; otherwise a monitor-only one is added (`p=none`) | Asks receivers to report problems; `p=none` never blocks anything. |
| **`_dtsmail.yourdomain.com`** (TXT) | — | Added: `v=dtsmail1 api=https://…` | How the apps find your server from your email address. |
| **`mail.yourdomain.com`** (CNAME) | — | Added for your **first** domain only | Your web version's address. |
| Website, `www`, verification and every other record | — | **Not touched** | |

Also changed, outside the DNS records:

- **Cloudflare Email Routing** is turned on for the domain, with a **catch-all rule** that delivers every address to
  DTS Mail. If you had already set up forwarding rules for particular addresses in Cloudflare, those addresses
  **keep forwarding where they did**; delete those rules in Cloudflare (*Email → Email Routing → Routing rules*) if you
  want that mail in DTS Mail too.
- **Cloudflare Email Sending** is turned on for the domain, so DTS Mail can send as it. Sending to people outside your
  own addresses needs Cloudflare's **Workers Paid** plan ($5 a month).
- In **DTS Mail**, the domain is added, you become its catch-all, and you get an address there.

**Timing:** new email usually starts arriving in DTS Mail within a few minutes. Some senders remember the old
settings for up to a day, so a few messages may still reach the old provider during that time. Outgoing email from a
newly added domain can take 5–15 minutes (rarely up to 24 hours) before Cloudflare accepts it.

---

## 7. Undoing a domain switch

- **Automatic:** if the test email sent during the switch doesn't arrive within about 2½ minutes, the old MX and SPF
  records are put back straight away. Nothing is lost; Claude or the wizard tells you what to check.
- **Later, by hand:** desktop app → **Settings → Domains** → the domain → **Undo email switch**. Your saved MX and SPF
  records come back and email flows to your old provider again. The extra records that were added (DKIM,
  `cf-bounce`, `_dtsmail`) stay, but do nothing on their own.
- To stop using DTS Mail altogether, run `/dts-mail:manage` and choose **uninstall**: it explains what will be
  removed and asks before deleting anything.

---

## 8. Updates and getting help

- **Updates happen by themselves.** Your server installs new versions within about an hour of Chuck releasing them,
  the web version always matches your server, and the desktop app updates itself.
- **Something wrong?** Run `/dts-mail:manage` in Claude Code and choose **status**, or describe the problem. Claude
  checks your server, explains what it finds in plain words, and suggests the fix.
- **Common problems and fixes:** [troubleshooting](plugins/dts-mail/skills/setup/references/troubleshooting.md).
- **How the pieces fit together:** [how it works](plugins/dts-mail/skills/setup/references/how-it-works.md).
