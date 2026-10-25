#!/usr/bin/env python3
"""Emails the user from Claude Code through their DTS Mail server, with a send-only API token (Mac and Linux;
Windows uses Email-Me.ps1). Standard library only.

  email_me.py setup                      # run by the user in their own terminal: asks for address and token
  email_me.py status                     # what's configured (never prints the token)
  email_me.py allow <address>            # add an allowed recipient
  email_me.py send --subject S --html body.html [--text body.txt] [--to addr ...] [--attach file ...]

Config lives in ~/.config/dts-mail/ (email-me.json, and email-me.token with mode 600). Mail only goes to the
addresses in "allowed"; the first one is the default. Prints OK:/FAIL: lines like the setup scripts.
"""
import argparse
import base64
import getpass
import html.parser
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

HOME = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "dts-mail")
CONFIG = os.path.join(HOME, "email-me.json")
TOKEN = os.path.join(HOME, "email-me.token")
DEFAULT_API = "https://dts-email-ingest.azurewebsites.net/api"
DOH_URL = "https://cloudflare-dns.com/dns-query"
MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024


def fail(msg, code=1):
    print(f"FAIL: {msg}")
    sys.exit(code)


def load_config():
    if not os.path.exists(CONFIG) or not os.path.exists(TOKEN):
        fail("not set up yet. Run in your own terminal: python3 " + os.path.abspath(__file__) + " setup", 3)
    with open(CONFIG, encoding="utf-8") as f:
        cfg = json.load(f)
    with open(TOKEN, encoding="utf-8") as f:
        token = f.read().strip()
    return cfg, token


def save_config(cfg):
    os.makedirs(HOME, mode=0o700, exist_ok=True)
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)


def discover(email):
    """The server from the domain's `_dtsmail` TXT record (v=dtsmail1 api=<url>), or None. Same rules as the apps."""
    domain = email.strip().lower().rsplit("@", 1)[-1].rstrip(".")
    if not re.fullmatch(r"[a-z0-9.-]+\.[a-z]{2,}", domain):
        return None
    url = f"{DOH_URL}?name={urllib.parse.quote('_dtsmail.' + domain)}&type=TXT"
    try:
        req = urllib.request.Request(url, headers={"accept": "application/dns-json"})
        with urllib.request.urlopen(req, timeout=5) as res:
            data = json.load(res)
    except (OSError, ValueError):
        return None
    if data.get("Status") != 0:
        return None
    for answer in data.get("Answer") or []:
        if answer.get("type") != 16:
            continue
        value = re.sub(r'"\s*"', "", answer.get("data", "").strip().strip('"')).strip()
        parts = value.split()
        if not parts or parts[0].lower() != "v=dtsmail1":
            continue
        api = next((p[4:] for p in parts if p.lower().startswith("api=")), None)
        if api and urllib.parse.urlparse(api).scheme == "https":
            return api.rstrip("/")
    return None


def post_send(api, token, body):
    req = urllib.request.Request(
        api.rstrip("/") + "/messages/send",
        data=json.dumps(body).encode("utf-8"),
        method="POST",
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return res.status, json.load(res)
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            detail = json.loads(text)
            text = detail.get("error") or detail.get("message") or text
        except ValueError:
            pass
        return e.code, text[:300]
    except OSError as e:
        fail(f"could not reach {api}: {e}")


class _Text(html.parser.HTMLParser):
    """Plain-text version of the HTML body, for mail apps that don't show HTML."""

    BLOCK = {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "table", "ul", "ol", "pre", "hr"}

    def __init__(self):
        super().__init__()
        self.out, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script", "head"):
            self.skip += 1
        elif tag == "li":
            self.out.append("\n- ")
        elif tag in self.BLOCK:
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in ("style", "script", "head"):
            self.skip = max(0, self.skip - 1)
        elif tag in self.BLOCK and tag != "li":
            self.out.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.out.append(data)

    def text(self):
        lines = [re.sub(r"[ \t]+", " ", l).strip() for l in "".join(self.out).splitlines()]
        return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip() + "\n"


def to_text(markup):
    p = _Text()
    p.feed(markup)
    return p.text()


def cmd_setup(args):
    print("DTS Mail: let Claude email you.")
    print("You need a send-only API token: DTS Mail desktop app -> Settings -> API tokens -> scope 'send'.\n")
    email = (args.email or input("Your email address: ")).strip().lower()
    if "@" not in email:
        fail("that isn't an email address.")
    api = args.api or discover(email) or DEFAULT_API
    print(f"Server: {api}")
    token = getpass.getpass("Paste the API token (dts_..., hidden): ").strip()
    if not token.startswith("dts_"):
        fail("API tokens start with dts_.")

    os.makedirs(HOME, mode=0o700, exist_ok=True)
    fd = os.open(TOKEN, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(token + "\n")
    previous = {}
    if os.path.exists(CONFIG):
        with open(CONFIG, encoding="utf-8") as f:
            previous = json.load(f)
    allowed = [email] + [a for a in previous.get("allowed", []) if a != email]
    save_config({"email": email, "api": api, "allowed": allowed})

    status, result = post_send(api, token, {
        "to": [email],
        "subject": "Claude can now email you",
        "text": "This is a test from the DTS Mail email-me skill. Ask Claude to \"email me\" anything.\n",
        "html": "<p>This is a test from the DTS Mail <b>email-me</b> skill.</p>"
                "<p>Ask Claude to &ldquo;email me&rdquo; anything.</p>",
    })
    if status >= 300:
        fail(f"the test email was not sent ({status}: {result}). Check the token, then run setup again.")
    print(f"OK: set up. A test email is on its way to {email}.")


def cmd_status(_):
    cfg, token = load_config()
    print("OK: set up.")
    print(json.dumps({"email": cfg.get("email"), "api": cfg.get("api"), "allowed": cfg.get("allowed", []),
                      "token": "saved" if token else None}, indent=2))


def cmd_allow(args):
    cfg, _ = load_config()
    address = args.address.strip().lower()
    if "@" not in address:
        fail("that isn't an email address.")
    if address not in cfg["allowed"]:
        cfg["allowed"].append(address)
        save_config(cfg)
    print(f"OK: {address} can now receive email from Claude. Allowed: {', '.join(cfg['allowed'])}")


def cmd_send(args):
    cfg, token = load_config()
    allowed = [a.lower() for a in cfg.get("allowed", [])]
    to = [t.strip().lower() for t in (args.to or allowed[:1])]
    blocked = [t for t in to if t not in allowed]
    if blocked:
        fail(f"not an allowed recipient: {', '.join(blocked)}. Allowed: {', '.join(allowed)}. "
             f"The user can add one with: email_me.py allow <address>", 4)

    with open(args.html, encoding="utf-8") as f:
        markup = f.read()
    if args.text:
        with open(args.text, encoding="utf-8") as f:
            text = f.read()
    else:
        text = to_text(markup)

    attachments = []
    for path in args.attach or []:
        size = os.path.getsize(path)
        if size > MAX_ATTACHMENT_BYTES:
            fail(f"{path} is {size // (1024 * 1024)} MB; the limit is 50 MB per file.")
        with open(path, "rb") as f:
            attachments.append({
                "fileName": os.path.basename(path),
                "contentType": mimetypes.guess_type(path)[0] or "application/octet-stream",
                "contentBase64": base64.b64encode(f.read()).decode("ascii"),
            })

    body = {"to": to, "subject": args.subject, "text": text, "html": markup}
    if attachments:
        body["attachments"] = attachments
    status, result = post_send(cfg["api"], token, body)
    if status == 401:
        fail("the token was refused (revoked or expired). Create a new one and run setup again.")
    if status >= 300:
        fail(f"{status}: {result}")
    print(f"OK: sent \"{args.subject}\" to {', '.join(to)}.")


def main():
    parser = argparse.ArgumentParser(description="Email yourself from Claude Code through DTS Mail.")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("setup")
    p.add_argument("--email")
    p.add_argument("--api", help="server API URL, when the domain has no _dtsmail record")
    p.set_defaults(func=cmd_setup)
    sub.add_parser("status").set_defaults(func=cmd_status)
    p = sub.add_parser("allow")
    p.add_argument("address")
    p.set_defaults(func=cmd_allow)
    p = sub.add_parser("send")
    p.add_argument("--subject", required=True)
    p.add_argument("--html", required=True, help="file with the HTML body")
    p.add_argument("--text", help="file with the plain-text body (default: made from the HTML)")
    p.add_argument("--to", action="append", help="recipient (default: the first allowed address)")
    p.add_argument("--attach", action="append", help="file to attach (repeatable)")
    p.set_defaults(func=cmd_send)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
