# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
mix setup              # install deps, create DB (unused), build assets
mix phx.server         # start server at localhost:4000
iex -S mix phx.server  # start with interactive shell
mix test               # run tests
mix format             # format code
```

## What this is

A Phoenix/Elixir bot that monitors board games on wargear.net and sends Slack notifications. Tracks game state (turn changes, eliminations, winners, reminders) using Google Sheets as the persistence layer — there is no database (Postgrex is commented out).

Secondary feature: a daily cron job that pulls crypto market breadth data from TradingView and appends it to a separate Google Sheet.

## Architecture

**Startup sequence** (`application.ex`):
1. `Spitegear.Repo` starts the Postgres connection pool.
2. A one-shot `Task` calls `Spitegear.Games.resume_games/0`, which queries for all games where `finished IS NULL` and starts a `GamePoller` for each.
3. `Spitegear.Worker.SlackMessenger` (GenServer) subscribes to the `"slack_messages"` PubSub topic and forwards messages to the Slack API.

**Per-game polling** (`Worker.GamePoller`):
- One `GamePoller` GenServer per active game, supervised under `GameSupervisor` (DynamicSupervisor).
- Polls `wargear.net/games/view/:id` every 20 seconds via `HTML.ViewScreen`, which uses HTTPoison + Floki to scrape the game page.
- Detects turn changes, new eliminations, and winners; publishes to PubSub for Slack delivery.
- Sends reminder messages every 3 hours (waking hours, America/Chicago) if no new turn has started.
- On game completion, stops itself (`:stop, :normal`).

**Slack integration:**
- Incoming events arrive at `POST /api/slack/events`. A wargear.net game URL in a Slack message triggers a new `GamePoller`.
- Outbound messages go through `Spitegear.PubSub.msg/2` → PubSub → `SlackMessenger` → `Slack.API`.
- Message text templates are in `Slack.Message`.

**Persistence** (`Spitegear.Games` context):
- `games` table — one row per wargear game; `finished IS NULL` means the game is active.
- `turns` table — one row per game (the *current* turn); upserted by `game_id` on each turn change or reminder.
- `upsert_game/1` and `upsert_turn/1` use `on_conflict` so callers don't need to distinguish insert vs update.

## Required environment variables

| Variable | Used by |
|---|---|
| `SLACK_AUTH_TOKEN` | Slack API calls |
| `DATABASE_URL` | Postgres connection (prod only, e.g. `ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Phoenix endpoint (prod only, generate with `mix phx.gen.secret`) |
| `PHX_HOST` / `PORT` | Phoenix endpoint (prod only) |
| `WARGEAR_USERNAME` | wargear.net login for cookie refresh job |
| `WARGEAR_PASSWORD` | wargear.net login for cookie refresh job |

## Deployment

Deployed on Fly.io (`fly.toml`). Release config in `rel/env.sh.eex`. Assets built with `mix assets.deploy` (minifies Tailwind + esbuild, runs `phx.digest`).
