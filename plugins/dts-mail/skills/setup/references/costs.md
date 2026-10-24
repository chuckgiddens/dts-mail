# What DTS Mail costs to run

You pay Azure and Cloudflare directly; Chuck doesn't charge anything. Rough figures for a household (a few people,
a few thousand emails a month). Prices change, so check Azure Cost Management after the first month.

| Item | Typical monthly cost | Notes |
|---|---|---|
| Cloudflare Workers Paid | **$5** | Needed to send to outside addresses. Includes 3,000 outgoing emails, then $0.35 per 1,000. Receiving (Email Routing) is free. |
| Azure Function App (Flex Consumption) | $0 – $2 | Pay per use with a monthly free grant; it sleeps when idle. The hourly update check and incoming mail are tiny. |
| Azure Storage | $0.10 – $1 | Mail and attachments (about $0.02 per GB-month) plus small per-request charges from the apps checking for new mail. |
| Log Analytics / Application Insights | $0 – $2 | Server logs, capped at 0.5 GB a day so a fault can't run up a bill; light use usually fits the free allowance. |
| Static Web App | $0 | Free plan. |
| AI (optional) | cents – a few dollars | Pay per use: each incoming email is checked once by the junk filter; summaries and writing help when used. |

**Usual total: about $5–8 a month**, most of it the Cloudflare plan.

Ways to keep it low:
- Skip AI (junk filtering then uses your blocked/safe sender lists and Cloudflare's own checks).
- Set an Azure budget alert: portal → *Cost Management* → *Budgets* → scope your resource group → e.g. $10/month.
- Delete large old attachments you don't need; storage is the only cost that grows over time.

To see actual spend: Azure portal → your resource group (default `dtsmail`) → **Cost analysis**.
