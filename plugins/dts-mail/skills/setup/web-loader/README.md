# DTS Mail web loader

The friend's Static Web App serves only this folder. It holds no app code: `loader.js` asks the friend's own mail
server which web build matches its API (`GET <apiBaseUrl>/version` → `web.base`) and starts that build from the public
release channel (`https://dtsmailreleases.blob.core.windows.net/server/web/<version>/`). When the server updates
itself, the web client follows on the next page load, so this site never needs redeploying for app updates.

| File | Purpose |
|---|---|
| `index.html` | Page shell: icons, manifest, a spinner in `#root` (the app replaces it), then `loader.js` |
| `loader.js` | Reads `config.json`, calls `/version`, sets `window.__DTS_CONFIG__ = { apiBaseUrl }`, injects the build's stylesheet, modulepreload and module-script tags. Shows a message with *Try again* when the config is missing, the server can't be reached (retries every 20 s), or the server has no web build yet (retries every minute) |
| `config.json` | `{ "apiBaseUrl": "https://<function-app>.azurewebsites.net/api" }`: the only per-friend file; the setup skill writes it |
| `staticwebapp.config.json` | SPA fallback; CSP allowing scripts, styles and fonts from the release origin and API/queue calls over https; no-cache for the three loader files |
| icons, `manifest.webmanifest` | Same as the main web app (installable, registers as a `mailto:` handler via `/?mailto=%s`) |

Invitation links (`/#invite?email=…&code=…`) and `/?mailto=…` keep working: the loader never navigates, so the app
reads them from the address bar as usual.

## Deploying

Copy the folder to a temporary directory, write the real `config.json` there, then:

```bash
npx --yes @azure/static-web-apps-cli deploy <dir> --deployment-token <token> --env production
```

The token comes from `az staticwebapp secrets list -n <static-web-app> -g <resource-group> --query properties.apiKey -o tsv`.
Redeploy only when this folder changes (a new kit version) or the API address changes.
