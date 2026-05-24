# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix setup              # install deps, create DB, build assets
mix phx.server         # start server at localhost:4001
iex -S mix phx.server  # start with interactive shell
mix test               # run all tests
mix test test/path/to/test.exs        # run a single test file
mix test test/path/to/test.exs:42     # run a single test by line number
mix credo              # lint (must pass before pushing — CI enforces it)
mix format             # format code
mix spitegear.create_user <username> <password>  # create an admin user (hashed, stored in DB)
```

Local secrets go in `config/dev.secret.exs` (gitignored). Slack posting is disabled in dev via `config :spitegear, :post_to_slack, false`.

## What this is

A Phoenix/Elixir bot that monitors board games on wargear.net and sends Slack notifications. Tracks game state (turn changes, eliminations, winners, reminders) using Postgres.

Secondary feature: a cron job that pulls crypto market breadth data from TradingView.

## Architecture

**Startup sequence** (`application.ex`):
1. `Spitegear.Repo` starts the Postgres connection pool.
2. A one-shot `Task` calls `Spitegear.Games.resume_games/0`, which queries for all games where `finished IS NULL` and starts a `GamePoller` for each.
3. `Spitegear.Worker.SlackMessenger` (GenServer) subscribes to the `"slack_messages"` PubSub topic and forwards messages to the Slack API.

**Per-game polling** (`Worker.GamePoller`):
- One `GamePoller` GenServer per active game, supervised under `GameSupervisor` (DynamicSupervisor).
- Two-layer detection: polls `Wargear.History` (REST API `/rest/GetHistoryUpdate/:id`) every 20 seconds for cheap turn-change detection; only fetches the full `HTML.ViewScreen` (HTTPoison + Floki scrape of `/games/view/:id`) when a new `turnid` is detected or for up to 10 minutes of 1-minute polls after a turn change.
- Detects turn changes, new eliminations, and winners; publishes to PubSub for Slack delivery.
- Sends reminder messages every 3 hours (waking hours, America/Chicago) if no new turn has started.
- On game completion, stops itself (`:stop, :normal`).
- Seeds `last_round` from DB on init so restarts don't re-announce already-completed rounds.

**Round tracking** (`Games.completed_rounds/1`):
- Walks `turn_history` chronologically and detects cycle boundaries when a player reappears — no dependency on `game_deaths`.
- Posts a "round complete" announcement to `#spitegear` at each round end; posts turn stats every 5 rounds to `#spitegear_test`.

**Cookie management** (`Wargear.Login`):
- Biweekly Quantum cron job (`0 3 1,15 * *`) logs out and back in to refresh the wargear.net session cookie, stored in the `settings` table.
- Login requires a two-step flow: GET `/player/login` first (to collect tracking cookies), then POST credentials with those cookies.
- `ViewScreen.get_game` auto-recovers from expired sessions: detects `login_required=1` in the response, calls `Login.refresh_cookie()`, and retries once.

**Slack integration:**
- Incoming events arrive at `POST /api/slack/events`. A wargear.net game URL in a Slack message triggers a new `GamePoller`.
- Outbound messages go through `Spitegear.PubSub.msg/2` → PubSub → `SlackMessenger` → `Slack.API`.
- Message text templates are in `Slack.Message`.

**Persistence** (`Spitegear.Games` context):
- `games` — one row per wargear game; `finished IS NULL` means active.
- `turns` — one row per game (the *current* turn); upserted by `game_id`.
- `turn_history` — append-only log of completed turns; used for round counting and turn stats.
- `game_deaths` — one row per eliminated player per game.
- `settings` — key/value store for runtime config (e.g. `wargear_cookie`, `wargear_api_key`). Accessed via `Spitegear.Settings.get/put`.

**Admin UI**: LiveView pages at `/admin`, `/admin/games`, `/admin/games/:game_id`.

## Required environment variables

| Variable | Used by |
|---|---|
| `SLACK_AUTH_TOKEN` | Slack API calls |
| `DATABASE_URL` | Postgres connection (prod only, e.g. `ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Phoenix endpoint (prod only, generate with `mix phx.gen.secret`) |
| `PHX_HOST` / `PORT` | Phoenix endpoint (prod only) |
| `WARGEAR_USERNAME` | wargear.net login for cookie refresh job |
| `WARGEAR_PASSWORD` | wargear.net login for cookie refresh job |

`wargear_api_key` is stored in the `settings` DB table (not an env var) and must be set manually.

## Deployment

Deployed on a self-hosted Beelink server (192.168.1.72 on local network, `spitegear.duckdns.org` externally) via GitHub Actions (`.github/workflows/deploy.yml`). The deploy job runs on a `self-hosted` runner, writes secrets to `$HOME/spitegear/.env`, pulls the latest code, then runs `make deploy` (builds a Docker image and restarts the container with `--env-file`). Assets built with `mix assets.deploy`.

To run commands on the deployed app:
```bash
ssh beelink "docker exec spitegear bin/spitegear rpc 'IO.inspect(SomeModule.some_function())'"
```
