# `BuildTheHosts`

A GitHub Action that builds **ready-to-use hosts blocklists** for multiple profiles (desktop, mobile, …) and publishes them to a rolling `latest` release — no servers, no daemons, no telemetry.

In plain terms: 
    👉 you describe *what* to block in a few plain text files,
    👉 GitHub rebuilds the lists on a schedule,
    👉 you download the finished `*-hosts.blocked` file and drop it into `/etc/hosts`.

You stay in control of **what gets blocked and what doesn't**.

---

## What you get

For every profile folder under `profiles/`, the workflow produces one asset:

```
desktop-hosts.blocked
mobile-hosts.blocked
```

…attached to the **`latest`** release, with stable URLs you can bookmark or feed to a script:

```
https://github.com/<owner>/<repo>/releases/latest/download/desktop-hosts.blocked
https://github.com/<owner>/<repo>/releases/latest/download/mobile-hosts.blocked
```

Add `profiles/tv/` tomorrow and a `tv-hosts.blocked` asset appears automatically — no workflow edit.

---

## How it works (very briefly, non-technical)

- Reads a list of source URLs from each profile
- Downloads them, extracts just the domains
- Applies that profile's whitelist and blacklist
- Writes a clean `0.0.0.0 domain` hosts file
- Publishes it to the `latest` release

No magic, no background services, no third-party trackers. The only network traffic is the blocklist sources you choose.

---

## Requirements

You don't install anything. GitHub's `ubuntu-latest` runners already have everything the build needs:

- `bash`, `curl`, `sed`, `awk`, `grep`, `sha256sum`

If you want to run the build locally, `bash` + `curl` is enough.

---

## Repository layout

```
profiles/
  desktop/
    sources.txt      # one URL or local path per line
    blacklist.txt    # optional — always-blocked domains
    whitelist.txt    # optional — allowed domains or regex: patterns
    headers.txt      # optional — prepended verbatim to the output
  mobile/
    sources.txt
    ...
build.sh             # the whole build, ~150 lines of bash
.github/workflows/
  build.yml          # discover profiles → build matrix → release
```

Every folder under `profiles/` is treated as one profile. Add a folder, get an asset.

---

## Configuration files (important)

The defaults are intentionally **opinionated**. You **must review and edit these files** to match *your* setup.

### `sources.txt`

A list of blocklist sources. Each line is either an `http(s)://` URL or a local path.

```
# example
https://big.oisd.nl/domainswild
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt
```

⚠️ **Warning**
If you copy an aggressive source list, it **will break major services**, including (but not limited to):

- social media
- messaging apps
- CDNs used by popular sites
- some app update servers

That is a property of *those lists*, not of this project. **Choose your sources deliberately.**

Sources that work well in this setup include:

- [OISD](https://oisd.nl/)
- [Hagezi/dns-blocklists](https://github.com/hagezi/dns-blocklists)
- [StevenBlack/hosts](https://github.com/StevenBlack/hosts/releases)
- [The Block List Project](https://blocklistproject.github.io/Lists/)
- [FMHY Filterlist](https://github.com/fmhy/FMHYFilterlist)

### `blacklist.txt`

Domains you explicitly **block**, no matter what the sources say.

- Highest priority
- Always applied first
- Useful for personal rules

```
ads.example.com
tracker.example.net
```

### `whitelist.txt`

Domains you explicitly **allow**, overriding any blocklist hit.

- Plain domain = exact match only (subdomains are **not** automatically allowed)
- `regex:` prefix = POSIX extended regex; you write the `^…$` anchors yourself

```
video.example.com
regex:^video-[A-Za-z0-9]{4}-[0-9]\.xx\.example\.com$
```

> **Tip:** use `[^.]*` instead of `.*` in regexes when you mean "one label, not many".
> `.*` matches dots, so `^search.*\.example\.com$` also matches `search.a.b.example.com`.
> `^search[^.]*\.example\.com$` matches `search-api.example.com` but not `search.a.b.example.com`.

### `headers.txt`

The static header at the top of the generated file — localhost entries, IPv6 defaults, OS-specific lines. Optional; if missing, only an auto-generated header block is added.

```
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
```

---

## Using the output

Download the asset you want:

```bash
curl -fL -o desktop-hosts.blocked \
  https://github.com/<owner>/<repo>/releases/latest/download/desktop-hosts.blocked
```

Then, carefully — this **replaces** your system file:

```bash
sudo cp /etc/hosts /etc/hosts.bak
sudo cp desktop-hosts.blocked /etc/hosts
```

Keep `/etc/hosts.bak` around. You will want it the first time a list is more aggressive than you expected.

---

## Running it yourself (optional)

> **Running it locally? You probably want the other repo**
>
> This repository is the **CI-first** version. It is designed to be
> forked, scheduled, and downloaded from — not run on your own machine.
> It has **no archive cache** and **no `--offline` mode**, because on
> GitHub's runners both features are dead weight: every run starts on a
> fresh machine, so a cache has nothing to warm up.
>
> If you actually want to run the build locally, use
> [`watermellon999/GimmeThaHosts`](https://github.com/watermellon999/GimmeThaHosts)
> instead. That version keeps per-URL archives and supports `--offline`,
> so repeated runs are fast and the build still works with no network.
>
> The snippet below is here only for contributors who want to test a
> change to `build.sh` before opening a PR — it is not the intended
> way to use this project.

The build is a single bash script. To try it locally:

```bash
./build.sh profiles/desktop out/desktop-hosts.blocked
```

It writes `out/desktop-hosts.blocked` and `out/desktop.log`, and never touches `/etc/hosts`. Inspect before copying.

---

## Schedule and triggers

The workflow runs:

- **Daily** at 03:00 UTC (sources change often)
- **On push** to `main` touching `profiles/`, `build.sh`, or the workflow
- **Manually**, via *Actions → build-hosts → Run workflow*

Each run replaces the assets on the `latest` release. If you also want dated snapshots, add a second release step with `tag_name: build-${{ github.run_number }}`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build succeeds but the asset is empty | `sources.txt` lines all failed and `blacklist.txt` is empty | check logs in the *Build* step; verify URLs |
| A domain you allow is still blocked | listed in `blacklist.txt`, or whitelisted only as an exact match while the blocked form is a subdomain | add the subdomain or use `regex:` |
| A domain you block still resolves | appears in `whitelist.txt` or in a source that whitelisted it | whitelist wins; remove it |
| Release step fails with "Resource not accessible" | workflow permissions | *Settings → Actions → General → Workflow permissions* → **Read and write** |
| Asset missing for one profile | that profile's build failed | see its matrix leg's log; other profiles still published |

---

## License

This project is licensed under the **GNU Affero General Public License v3 (AGPLv3)**.

You are free to use, modify, and share it — but improvements and network-used modifications must remain open.

---

## Special thanks ❤️

- All **blocklist maintainers and contributors**
- The **privacy, security, and FLOSS communities**
- Everyone sharing knowledge, tools, and data openly

This project stands on the shoulders of a lot of unpaid, often invisible work.
