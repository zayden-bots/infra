# Zayden infra

Deployment and workspace tooling for the Zayden repos under the GitHub org `zayden-bots`. This repo has no Rust code. It holds the compose file, the deployed config, the env template, helper scripts and the shared tooling files that every Rust repo copies.

The repos are checked out side by side in one parent folder:

| Repo | Contents | Depends on |
|---|---|---|
| `schema` | migrations, `schema::MIGRATOR`, `schema::migrator()` | nothing |
| `platform` | `zayden-core`, `zayden-app`, `zayden-graphics`, `bot-runtime` | `schema` |
| `modules` | one crate per feature under `crates/` | `platform`, `schema` |
| `bots` | the bot binaries (`bots/zayden/`, `llama`, `maria`, `worker`), `docker/Dockerfile.bot` | `modules`, `platform` |
| `dashboard` | Topcoat dashboard (`web/`), `docker/Dockerfile.web` | `modules`, `platform`, `schema` |
| `infra` | this repo | none |

Dependencies only point up the table. `bots` and `dashboard` do not depend on each other.

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Runs `zayden`, `llamabot`, `maria`, `worker` and `dashboard` from the GHCR images |
| `config/zayden.toml` | The deployed config, shared by the bot and the dashboard |
| `.env.example` | Placeholder-only list of environment variables |
| `scripts/checkout.sh` | Clones missing sibling repos and links the config |
| `scripts/dev-link.sh` | Toggles local `[patch]` entries for cross-repo work |
| `scripts/sync-standards.sh` | Copies the shared tooling files into every Rust repo |
| `template/` | Source of the shared tooling files and the dev patch |
| `.github/workflows/ci.yml` | Validates the compose file, the scripts and the dev patch |

`template/` holds `rust-toolchain.toml`, `rustfmt.toml`, `clippy.toml`, `cargo-config.toml` (installed as `.cargo/config.toml`) and `dev-patch.toml`.

## First checkout

Clone this repo as a sibling-to-be, then run the script. It clones any of `schema`, `platform`, `modules`, `bots` and `dashboard` that is missing from the parent folder, and prints `<repo>: present` for the rest. It then symlinks `bots/config.toml` and `dashboard/config.toml` to `infra/config/zayden.toml`. Both links are gitignored in their repos.

```sh
git clone https://github.com/zayden-bots/infra
./infra/scripts/checkout.sh
```

## Local development

Internal crates are git dependencies in each repo's root `Cargo.toml`, so a change in one repo is not seen by another until it is pushed. To work across repos without pushing, link the checkouts:

```sh
./scripts/dev-link.sh on       # writes ../.cargo/config.toml
./scripts/dev-link.sh status   # prints "dev-link: on" or "dev-link: off"
./scripts/dev-link.sh off      # removes it
```

`on` copies `template/dev-patch.toml` to `../.cargo/config.toml` (the parent folder). It holds a `[patch]` entry for every org crate, pointing at the sibling checkouts. The file starts with the marker `# managed by infra/scripts/dev-link.sh`. If `../.cargo/config.toml` exists without that marker, all three commands refuse to touch it and exit 1.

A `Cargo.lock` written while the link is on must never be committed. Run `dev-link.sh off` and `cargo update <crate>` (or `git restore Cargo.lock`) first.

The shared tooling files are owned by `template/`. Copy them into every Rust repo, or report drift without changing anything:

```sh
./scripts/sync-standards.sh           # copy
./scripts/sync-standards.sh --check   # diff each file, exit 1 on drift
```

Lint tables in each root `Cargo.toml` are kept identical across repos by hand.

## Configuration

`config/zayden.toml` is the deployed config. The bot and the dashboard read `config.toml` from the working directory. In compose it is mounted read-only at `/app/config.toml`. Locally, `checkout.sh` symlinks it into `bots/` and `dashboard/`.

`.env.example` lists the environment variables with placeholders. Copy it to `.env` and fill it in. `.env` is gitignored; never commit it.

- Required: `DATABASE_URL`, `KOFI_VERIFICATION_TOKEN`.
- Per module: `BUNGIE_API_KEY`, `AI_PROVIDER_KEY`, `GOOGLE_API_KEY`, and `DISCORD_CLIENT_SECRET` for the dashboard.
- Optional: log webhooks, `DASHBOARD_COOKIE_KEY`, Pelican, Patreon, YouTube, Spotify, Jellyfin and Jellyseerr keys, custom bot keys, `LOG_FORMAT` and `METRICS_BIND_ADDR`. Each is commented out in the file with its notes.

Each bot has its own `DISCORD_TOKEN`. It lives in a per-bot env file next to `.env`, not in `.env`: `zayden.env`, `llamabot.env` and `maria.env`, each holding one line, `DISCORD_TOKEN=...`. Keep them out of git and set them to mode 600. The shared secrets stay in `.env`.

Compose reads `RUST_LOG` (default `info`), `IMAGE_TAG` (default `latest`), `METRICS_HOST` (default `127.0.0.1`) and `COMPOSE_PROFILES` from the environment or `.env`. Each service loads `.env` with `env_file`, plus its own `<bot>.env` for a bot, so `DATABASE_URL` and the other secrets reach the containers from there. The services run with `LOG_FORMAT=json`.

## Deploy

`docker-compose.yml` runs these services from images pushed to GHCR by each repo's `images` CI job:

| Service | Image | Env files | Metrics port | Notes |
|---|---|---|---|---|
| `zayden` | `ghcr.io/zayden-bots/zayden:${IMAGE_TAG:-latest}` | `.env`, `zayden.env` | 9100 | 1 GiB memory reservation, `palworld_uploads` volume; needs `CUSTOM_BOT_KEYS` and `CUSTOM_BOT_ACTIVE_KEY` so other bots can copy its emojis |
| `llamabot` | `ghcr.io/zayden-bots/llama:${IMAGE_TAG:-latest}` | `.env`, `llamabot.env` | 9102 | Zayden's modules plus llamad2; see below |
| `maria` | `ghcr.io/zayden-bots/maria:${IMAGE_TAG:-latest}` | `.env`, `maria.env` | 9104 | profile `maria`, off by default; AI chat only |
| `worker` | `ghcr.io/zayden-bots/worker:${IMAGE_TAG:-latest}` | `.env` | 9103 | scheduled jobs and broadcasts; needs `CUSTOM_BOT_KEYS` |
| `dashboard` | `ghcr.io/zayden-bots/dashboard:${IMAGE_TAG:-latest}` | `.env`, `zayden.env` | 9101 | host port 3000 maps to container port 3000; needs `CUSTOM_BOT_KEYS` and `CUSTOM_BOT_ACTIVE_KEY` to act as bots other than Zayden |

Every service mounts `config/zayden.toml` read-only at `/app/config.toml`. The metrics ports are published on `${METRICS_HOST:-127.0.0.1}`; set `METRICS_HOST` in `.env` to the interface your Prometheus scrapes. `zayden` and `llamabot` can also mount `config/radio.toml` at `/app/radio.toml`; that mount is commented out in the compose file until you create the file.

Deploy in this order:

1. The bots (`zayden`, `llamabot` and, if enabled, `maria`) and the worker, together. All of them run migrations on startup.

   ```sh
   docker compose pull zayden llamabot worker && docker compose up -d zayden llamabot worker
   ```

   With Maria enabled, add `maria` to both commands, or set `COMPOSE_PROFILES=maria` first.

2. The dashboard.

   ```sh
   docker compose pull dashboard && docker compose up -d dashboard
   ```

### LlamaBot

`llamabot` is a compose service. It runs the `llama` image, which is Zayden's module list plus llamad2, with its own `llamabot.env` holding its `DISCORD_TOKEN`. It boots in the Zayden slot as a custom bot. Compose's `restart: unless-stopped` is its supervisor.

It copies Zayden's application emojis with Zayden's token, which the `zayden` service seals into its `applications` row at startup. It needs `CUSTOM_BOT_KEYS` and `CUSTOM_BOT_ACTIVE_KEY` in `.env` to read it; without them it logs a warning and keeps only its own emojis. When rotating keys, add the new key to every process first (`zayden`, `llamabot`, `maria`, the worker and the dashboard), and only then make it the active key on Zayden.

### Maria

1. Create a Discord application and bot user. Enable the Server Members, Presence and Message Content intents; every bot requests all three.
2. Add `maria_id` under `[ids]` in `config/zayden.toml`.
3. Create `maria.env` next to `.env` with the bot's `DISCORD_TOKEN`, and set it to mode 600.
4. Enable the profile: set `COMPOSE_PROFILES=maria` in `.env` or the shell, or run `docker compose --profile maria up -d maria`.

Without the profile the stack starts without Maria, so `maria.env` can be missing.

Each new bot also needs a Prometheus scrape target on its metrics port and its name in the Loki alert matchers.

A contract migration (one that drops tables, columns or functions) breaks every binary still running older code. Push its `schema` commit only after every running binary, `llamabot` and `maria` included, runs code that no longer uses the dropped objects. The first bot or worker that starts afterwards applies it.

Check the compose file without starting anything. Every env file a service names must exist, so create empty ones first in a checkout without them:

```sh
touch .env zayden.env llamabot.env maria.env
COMPOSE_PROFILES=maria docker compose config --quiet
```

## Releasing a change across repos

Push upstream first. Then, in each downstream repo, in the order `platform`, `modules`, then `bots` and `dashboard`:

1. Update every org repo the lockfile pins, in one command: `cargo update schema` in `platform`, `cargo update schema zayden-app` in `modules`, `cargo update schema zayden-app accounts` in `bots` and `dashboard`. One crate name moves its whole repo. Moving them together keeps the migrations a binary embeds in step with the queries its modules were checked against.
2. Regenerate `.sqlx/` if queries changed (not needed in `bots`, which has no queries).
3. Run the checks.
4. Commit `Cargo.lock`.

Use one ref per org repository: never give two entries for the same repo different `branch`, `tag` or `rev` values. CI enforces this in `modules`, `bots` and `dashboard`.

## CI

`.github/workflows/ci.yml` runs one job, `compose and scripts`, on pushes to `main`, pull requests and manual dispatch:

- `docker compose config --quiet` with the `maria` profile on and empty env files.
- `bash -n` and `shellcheck` on `scripts/*.sh`.
- A check that `template/dev-patch.toml` parses as TOML.
