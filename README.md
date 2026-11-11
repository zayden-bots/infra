# Zayden infra

Deployment and workspace tooling for the Zayden repos under the GitHub org `zayden-bots`. This repo has no Rust code. It holds the compose file, the deployed config, the env template, helper scripts and the shared tooling files that every Rust repo copies.

The repos are checked out side by side in one parent folder:

| Repo | Contents | Depends on |
|---|---|---|
| `schema` | migrations, `schema::MIGRATOR`, `schema::migrator()` | nothing |
| `platform` | `zayden-core`, `zayden-app`, `zayden-graphics`, `bot-runtime` | `schema` |
| `modules` | one crate per feature under `crates/` | `platform`, `schema` |
| `bots` | the bot binary (`bots/zayden/`), `docker/Dockerfile.bot` | `modules`, `platform` |
| `dashboard` | Topcoat dashboard (`web/`), `docker/Dockerfile.web` | `modules`, `platform`, `schema` |
| `infra` | this repo | none |

Dependencies only point up the table. `bots` and `dashboard` do not depend on each other.

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Runs the `bot` and `web` services from the GHCR images |
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

- Required: `DATABASE_URL`, `DISCORD_TOKEN`, `KOFI_VERIFICATION_TOKEN`.
- Per module: `BUNGIE_API_KEY`, `AI_PROVIDER_KEY`, `GOOGLE_API_KEY`, and `DISCORD_CLIENT_SECRET` for the dashboard.
- Optional: log webhooks, `DASHBOARD_COOKIE_KEY`, Pelican, Patreon, YouTube, Spotify, Jellyfin and Jellyseerr keys, custom bot keys, `LOG_FORMAT` and `METRICS_BIND_ADDR`. Each is commented out in the file with its notes.

Compose reads `DATABASE_URL` (required), `RUST_LOG` (default `info`) and `IMAGE_TAG` (default `latest`) from the environment or `.env`.

## Deploy

`docker-compose.yml` runs three services from images pushed to GHCR by each repo's `images` CI job:

| Service | Image | Notes |
|---|---|---|
| `bot` | `ghcr.io/zayden-bots/zayden:${IMAGE_TAG:-latest}` | 1 GiB memory reservation, `palworld_uploads` volume |
| `worker` | `ghcr.io/zayden-bots/worker:${IMAGE_TAG:-latest}` | scheduled jobs and broadcasts; needs `CUSTOM_BOT_KEYS` |
| `web` | `ghcr.io/zayden-bots/dashboard:${IMAGE_TAG:-latest}` | host port 3100 maps to container port 3000 |

Deploy in this order:

1. The Zayden bot and the worker, together. Both run migrations on startup.

   ```sh
   docker compose pull bot worker && docker compose up -d bot worker
   ```

2. The dashboard.

   ```sh
   docker compose pull web && docker compose up -d web
   ```

3. LlamaBot, on its VPS. It runs the same bot binary with its own `DISCORD_TOKEN`, outside compose, and is deployed by hand. It also runs migrations on startup. Redeploy it whenever the bot binary or the migrations change.

Check the compose file without starting anything:

```sh
docker compose config --quiet
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

- `docker compose config --quiet` with a placeholder `DATABASE_URL`.
- `bash -n` and `shellcheck` on `scripts/*.sh`.
- A check that `template/dev-patch.toml` parses as TOML.
