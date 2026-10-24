# Creating the Cloudflare API token for DTS Mail

DTS Mail needs one Cloudflare API token. It lets setup (and later the server itself) deploy the inbound-mail Worker,
turn on Email Routing for your domain, add the DNS records email needs, onboard the domain for Email Sending, and
send mail through Cloudflare's SMTP relay (the token is also the SMTP password).

**Never paste the token into the Claude chat.** Setup opens a small "DTS Mail - Cloudflare" window for it.

## Before you start

1. Your domain is on Cloudflare and shows **Active** (dashboard → your domain → *Overview*).
2. **Workers Paid plan** ($5/month, includes 3,000 outgoing emails a month, then $0.35 per 1,000): needed to send
   mail to anyone outside your own verified addresses. Receiving mail works on the free plan. To add it:
   dashboard → **Workers & Pages** → **Plans** → *Workers Paid*. (You can set everything up first and add it later;
   only outgoing mail waits for it.)

## 1. Copy your Account ID

Dashboard → click your domain → **Overview**. In the right-hand column, under **API**, copy **Account ID**
(a 32-character code). It isn't secret: you can paste it into the chat when Claude asks.

## 2. Create the token

An **account-owned** token is recommended (it keeps working if your user login changes, and Cloudflare recommends it
for SMTP). If you don't see account tokens, a user token (*My Profile → API Tokens*) works the same way.

1. Dashboard → **Manage Account** (left menu) → **Account API Tokens** → **Create Token**.
2. At the bottom, **Custom token** → **Get started**.
3. **Token name**: `DTS Mail`.
4. **Permissions** — add these seven rows (the first drop-down chooses Account or Zone; type in the second one to
   find the name; set the third to **Edit**, or **Read** where it says so):

   | Scope | Permission | Level |
   |---|---|---|
   | Account | Workers Scripts | Edit |
   | Account | Email Routing Addresses | Edit |
   | Account | Email Sending | Edit |
   | Zone | Zone | Read |
   | Zone | DNS | Edit |
   | Zone | Zone Settings | Edit |
   | Zone | Email Routing Rules | Edit |

5. **Zone Resources**: *Include* → **All zones from an account** → your account (so adding another domain later
   just works). If you prefer, *Specific zone* → your domain (you'll edit the token to add domains later).
   For a user token, **Account Resources**: *Include* → your account.
6. **Client IP Address Filtering**: leave empty (Azure's addresses change).
7. **TTL**: leave without an end date. If it expires, sending and setup tasks stop working until you replace it
   (`/dts-mail:manage` → rotate token).
8. **Continue to summary** → **Create Token**. Copy the token (it's shown once) and paste it into the
   *DTS Mail - Cloudflare* window when setup opens it.

Cloudflare's API reference spells the Edit level as "Write" (e.g. "DNS Write"); in the dashboard it's "Edit".

## What each permission is for

| Permission | Used for | API calls |
|---|---|---|
| Zone: Read | find your domain's zone | `GET /zones` (accepted: *Zone Read*) |
| DNS: Edit | MX/SPF/DKIM/DMARC records, `_dtsmail` discovery record, `mail.` CNAME | `GET/POST/PUT/DELETE /zones/{id}/dns_records` (accepted: *DNS Write*) |
| Zone Settings: Edit | turn on Email Routing and read the records it needs | `POST /zones/{id}/email/routing/enable`, `GET …/email/routing`, `GET …/email/routing/dns` (accepted: *Zone Settings Write*/*Read*) |
| Email Routing Rules: Edit | catch-all rule: all mail → the DTS Mail Worker | `PUT /zones/{id}/email/routing/rules/catch_all` (accepted: *Email Routing Rules Write*) |
| Email Routing Addresses: Edit | outside addresses that aliases forward to | `GET/POST/DELETE /accounts/{id}/email/routing/addresses` (accepted: *Email Routing Addresses Write*) |
| Workers Scripts: Edit | deploy the inbound-mail Worker `dts-email-ingest` | `PUT /accounts/{id}/workers/scripts/{name}` (accepted: *Workers Scripts Write*) |
| Email Sending: Edit | SMTP relay (`smtp.mx.cloudflare.net:465`, user `api_token`) and onboarding the domain for sending | SMTP; `…/email/sending/subdomains`, `…/email/sending/send` |

Sources: Cloudflare API reference pages for
[List Zones](https://developers.cloudflare.com/api/resources/zones/methods/list/),
[Create DNS Record](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/),
[Enable Email Routing](https://developers.cloudflare.com/api/resources/email_routing/methods/enable/),
[Get Email Routing settings](https://developers.cloudflare.com/api/resources/email_routing/methods/get/),
[Email Routing DNS](https://developers.cloudflare.com/api/resources/email_routing/subresources/dns/methods/get/),
[Update catch-all rule](https://developers.cloudflare.com/api/resources/email_routing/subresources/rules/subresources/catch_alls/methods/update/),
[Create destination address](https://developers.cloudflare.com/api/resources/email_routing/subresources/addresses/methods/create/),
[Upload Worker module](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/);
[Email Service SMTP](https://developers.cloudflare.com/email-service/api/send-emails/smtp/) ("Email Sending: Edit");
[Email Service pricing](https://developers.cloudflare.com/email-service/platform/pricing/) (Workers Paid for sending).
Cloudflare doesn't list the permission for the Email Sending REST endpoints; *Email Sending: Edit* is the one its
SMTP docs name, and setup's token check only warns if that part fails.
