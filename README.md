# OpenCode Web on EasyPanel

This directory builds a single, self-contained OpenCode Web container. It starts
the official browser UI automatically with:

```text
opencode web --hostname 0.0.0.0 --port 4096
```

It deliberately does **not** start the TUI and does **not** publish a host port.
EasyPanel routes HTTPS traffic internally to port `4096`.

## Verified design choices

- OpenCode documents `opencode web` as the browser interface, while `opencode
  serve` is the headless HTTP API. This image therefore uses `opencode web`.
- Authentication is OpenCode HTTP Basic Auth, enabled with
  `OPENCODE_SERVER_PASSWORD`; `OPENCODE_SERVER_USERNAME` is optional but set
  explicitly here.
- OpenCode documents global configuration in `~/.config/opencode` and session
  and application data in `~/.local/share/opencode`. Those locations are
  persistent volumes in this deployment.
- `GET /global/health` is the documented health endpoint. The healthcheck sends
  the configured Basic Auth credentials, so a protected server can report as
  healthy.
- The image installs the official `opencode-ai` npm package **at image build
  time**, plus Node.js LTS, npm, pnpm, Python/pip, Git, SSH client, curl, bash,
  and Debian build tools. It contains no API key, GitHub token, or password.

Official references: [OpenCode Web](https://opencode.ai/docs/web/),
[OpenCode server](https://opencode.ai/docs/server/),
[OpenCode configuration](https://opencode.ai/docs/config/), and
[OpenCode storage](https://opencode.ai/docs/troubleshooting/).

## Files

```text
opencode/
├── Dockerfile
├── docker-compose.yml
├── docker-entrypoint.sh
├── .dockerignore
├── .env.example
├── .gitignore
└── README.md
```

Copy `.env.example` to `.env` only for a local Docker Compose deployment. Do
not commit the resulting `.env`; in EasyPanel, put the same values in its
environment editor instead.

## Persistent storage

| Volume | Container path | Purpose |
| --- | --- | --- |
| `opencode_config` | `/home/opencode/.config/opencode` | OpenCode configuration, plugins, agents, commands, and skills |
| `opencode_data` | `/home/opencode/.local/share/opencode` | OpenCode sessions, provider auth, logs, and other app data |
| `opencode_state` | `/home/opencode/.local/state/opencode` | Runtime state kept across recreations |
| `opencode_cache` | `/home/opencode/.cache/opencode` | Provider and tooling cache; persisted to avoid needless re-downloads |
| `opencode_ssh` | `/home/opencode/.ssh` | Optional GitHub SSH identity and known hosts |
| `workspace` | `/workspace` | All projects: `/workspace/proyecto-1`, `/workspace/proyecto-2`, … |

The OpenCode process runs as the non-root `opencode` user and has read/write
access to all paths above. At startup, the entrypoint repairs a volume created
as `root` only when its root directory has the wrong owner, then immediately
drops privileges before starting OpenCode. This prevents the EasyPanel volume
ownership error without running OpenCode itself as `root`. In EasyPanel, make
each entry a **Volume** mount with the corresponding container path. Do not
replace these with an ephemeral container path.

## Recommended EasyPanel deployment: App service

OpenCode is one container, so an EasyPanel **App** service is the simplest
option and enables EasyPanel's scheduled volume backups.

1. Commit this `opencode/` directory to a private Git repository, or upload an
   archive containing it. Never commit `.env`.
2. In EasyPanel, create **New Service → App**. Under **Source**, choose the
   repository/upload. Set **Build Path** to `/opencode` when the directory is
   at repository root (or `/` if these files are the repository root).
3. Under **Build**, select **Dockerfile** and use `Dockerfile`. Do not add a
   start-command override; the image CMD starts OpenCode Web.
4. Under **Environment**, add at minimum:

   ```env
   OPENCODE_SERVER_USERNAME=opencode
   OPENCODE_SERVER_PASSWORD=<a-long-unique-password>
   ```

   Add provider keys, such as `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, only if
   you use those providers. Values in EasyPanel are secrets: do not put them in
   a Dockerfile, Compose file, repository, or project `opencode.json`.
5. Under **Storage**, create the six Volume mounts in the table above. Deploy
   after adding them. Confirm that the mounts are writable by the `opencode`
   user; named volumes are initialized with the image directories' ownership.
6. Under **Domains**, add the public hostname (for example,
   `code.example.com`), choose internal protocol **HTTP**, and set target port
   **4096**. Enable HTTPS with your certificate resolver and mark it primary.
   The process listens on `0.0.0.0:4096`, which is required for proxy access.
   Do **not** add a published port in EasyPanel's Advanced → Ports section.
7. Deploy and open `https://code.example.com`. The browser will request the
   OpenCode username and password configured above.

EasyPanel handles the reverse proxy and TLS. The browser and OpenCode are on
the same public origin, so no `--cors` flag is required. If you intentionally
use a separate frontend origin, configure only its exact URL with the official
`--cors` option after reviewing the OpenCode documentation.

### Docker Compose service alternative

If you prefer **New Service → Compose**, select this directory as the build
path and `docker-compose.yml` as the Compose file. Add the same environment
variables in EasyPanel, deploy, then create a domain pointing to service
`opencode`, HTTP, port `4096`.

The Compose file uses `expose: 4096`, not `ports:`. This keeps port 4096 on the
internal Docker network for EasyPanel/Traefik; it is not reachable directly
from the VPS public IP. EasyPanel's Compose documentation specifically advises
using Domains rather than published ports for public HTTP traffic.

The Compose option preserves volumes, but EasyPanel's built-in scheduled Volume
Backups currently apply to App and Box services, not Compose services. Prefer
the App-service route above when using EasyPanel-managed backup schedules.

## Local Docker Compose use

```bash
cp .env.example .env
# Edit .env and replace the example password.
docker compose up --build -d
```

This Compose file intentionally has no host `ports:` mapping. For a local-only
test, add a temporary override file (do not deploy it to EasyPanel):

```yaml
# compose.override.yml
services:
  opencode:
    ports:
      - "127.0.0.1:4096:4096"
```

Then visit `http://127.0.0.1:4096`; Basic Auth is still required. Remove the
override after testing if it is not needed.

## GitHub access without embedding credentials

Git and OpenSSH are in the image. The recommended persistent method is an SSH
key generated inside the `opencode_ssh` volume, not a token baked into the
image or repository.

1. In EasyPanel, open the running service's **Shell** and run:

   ```bash
   ssh-keygen -t ed25519 -C "opencode@your-domain" -f ~/.ssh/id_ed25519
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/id_ed25519
   cat ~/.ssh/id_ed25519.pub
   ```

2. Add the displayed public key to the GitHub repository as a deploy key.
   Enable write access only when OpenCode must push. A deploy key is normally
   scoped to one repository. For several repositories, use a distinct key and
   SSH host alias for each repository, or use a GitHub App with only the
   required repository permissions; never reuse one deploy key across repos.
3. Add GitHub's verified SSH host keys to `~/.ssh/known_hosts` before cloning.
   Validate the fingerprints against GitHub's published SSH key fingerprints;
   do not blindly trust an unverified network response.
4. Clone into `/workspace`, for example:

   ```bash
   git clone git@github.com:OWNER/REPOSITORY.git /workspace/proyecto-1
   ```

Protect backups of `opencode_ssh`: it contains a private key. An HTTPS token,
if your organization requires one, must be a fine-grained, least-privilege
GitHub token stored as an EasyPanel secret or a credential store on the
persistent volume—never in the image, Compose file, or Git remote URL. See
[GitHub's deploy-key guidance](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)
and [its SSH-host-key fingerprints](https://docs.github.com/en/enterprise-cloud@latest/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

## Updates, health, and backups

### Update OpenCode

The package is installed during build, so an image rebuild fetches the current
published package. On Docker Compose:

```bash
docker compose build --pull
docker compose up -d
```

On EasyPanel App or Compose, deploy again after pulling the repository change
or use **Force Rebuild** when you need to rebuild without Docker cache. Do not
delete or rename the volume mounts: images may be replaced, but the named
volumes preserve projects, sessions, configuration, and credentials.

### Verify the running service

The image healthcheck requests the documented endpoint:

```text
GET /global/health
```

It expects authenticated success and reports the container unhealthy if the
server does not respond successfully. Verify from the EasyPanel logs/status,
or from a trusted internal shell:

```bash
curl --user "$OPENCODE_SERVER_USERNAME:$OPENCODE_SERVER_PASSWORD" \
  http://127.0.0.1:4096/global/health
```

The response includes `healthy: true` and the OpenCode version.

### Back up `/workspace`

For the recommended App service, configure an external storage provider in
**Server Settings → Storage Providers**, then create a **Volume Backup** for
the `/workspace` mount. Use a unique remote destination such as
`opencode/workspace/`. Run it manually once, inspect the logs and remote files,
then schedule it. Enable object/version history at the backup provider because
EasyPanel volume backups are mirrors, not snapshots.

Also back up `opencode_config`, `opencode_data`, and `opencode_state` to
separate remote destinations if session history, OpenCode settings, and provider
authentication must be recoverable. Treat `opencode_data` and `opencode_ssh` as
sensitive: they can contain provider OAuth/API credentials and private SSH
keys. Encrypt them and restrict backup access. Test restoration into a
non-production volume before relying on any backup schedule.

## Operational checks

After first deployment, confirm:

- OpenCode Web, not the TUI, opens at the HTTPS domain.
- The service target is internal HTTP port `4096`; no public TCP port exists.
- Authentication challenges unauthenticated requests.
- `GET /global/health` succeeds with credentials.
- A project created under `/workspace` remains after **Restart** and **Deploy**.
- OpenCode settings and a test session remain after **Restart** and **Deploy**.
- `git --version`, `node --version`, `npm --version`, `pnpm --version`,
  `python3 --version`, and `pip3 --version` work in the EasyPanel shell.

See the current [EasyPanel App service documentation](https://easypanel.io/docs/services/app),
[Compose service documentation](https://easypanel.io/docs/services/compose), and
[Volume Backups documentation](https://easypanel.io/docs/backups/volumes) for
the corresponding UI controls.
