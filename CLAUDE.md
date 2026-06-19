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

## Architecture

**Startup sequence** (`application.ex`):
1. `Spitegear.Repo` starts the Postgres connection pool.
2. A one-shot `Task` calls `Spitegear.Games.resume_games/0`, which queries for all games where `finished IS NULL` and starts a `GamePoller` + `GameManager` pair for each.
3. `Spitegear.Worker.SlackMessenger` (GenServer) subscribes to the `"slack_messages"` PubSub topic and forwards messages to the Slack API.
4. `Spitegear.Logger.SlackErrorHandler` is added to the Erlang logger and posts `:error`-level log events to Slack.

**Per-game worker pair** (two GenServers per game, both supervised under `GameSupervisor` (DynamicSupervisor)):

- `Worker.GamePoller` — handles all HTTP I/O. Polls `Wargear.HTTP.History` every 20 seconds for cheap turn-change detection; fetches the full `Wargear.HTTP.ViewScreen` on a new `turnid` or for up to 10 one-minute polls after a turn change. Also dispatches async board image fetches (with exponential backoff) when a turn advances on an unfogged game. Notifies `GameManager` via cast on every successful fetch.
- `Worker.GameManager` — owns all game state. Receives fetch notifications from `GamePoller` and runs them through the `LiveGameState` pipeline. Dispatches async log re-fetches after turn advances. Stops itself on game completion (`:finish_game` cast).

**`LiveGameState` pipeline** (`live_game_state.ex`):

`LiveGameState` is a struct with current/prev snapshots of DB-persisted turns, view screens, and history API responses. Business logic runs as a chain of functions that each return the updated struct (no-ops when their precondition fails):

- History pipeline: `record_changed_history_response → send_reminder → announce_moving`
- View screen pipeline: `record_changed_view_screen_db → advance_turn → fetch_board_image_if_advanced → fetch_log_if_unfogged → announce_next_round → announce_next_turn → infer_deaths_from_skip → detect_eliminations → announce_winners`

Fogged games use `infer_deaths_from_skip` (detects eliminations from skipped positions in turn order); unfogged games use `detect_eliminations` (reads the view screen directly).

**Game log subsystem** (`game_log/`):

- `Wargear.HTTP.LogSnapshot` — fetches raw HTML log from wargear.net; stored in `game_log_snapshots`.
- `GameLog.Parser` — parses individual log rows into typed `GameLogEvent` attrs.
- `GameLog.Processor` — processes/upserts snapshots into `game_log_events`. Key entry points: `process_all/0`, `reprocess_unrecognized/0`, `refetch_and_process/1` (called automatically after each turn advance on unfogged games), `fill_defenders/0` (second-pass extraction of defender/territory fields).

**Cookie management** (`Wargear.HTTP.Login`):
- Biweekly Quantum cron job (`0 3 1,15 * *`) logs out and back in to refresh the wargear.net session cookie, stored in the `settings` table.
- Login requires a two-step flow: GET `/player/login` first, then POST credentials with those cookies.
- `ViewScreen.get_game` auto-recovers from expired sessions by detecting `login_required=1`, calling `Login.refresh_cookie()`, and retrying once.

**Slack integration:**
- Incoming events arrive at `POST /api/slack/events`. A wargear.net game URL in a message triggers a new `GamePoller`/`GameManager` pair.
- Outbound messages go through `Spitegear.PubSub.msg/2` → PubSub → `SlackMessenger` → `Slack.API`.
- Message text templates are in `Slack.Message`; the DB-editable versions are in `MessageTemplates` / `message_templates` table.

**Persistence** (`Spitegear.Games` context):
- `games` — one row per wargear game; `finished IS NULL` means active.
- `live_game_state_turns` — open/closed turn records (current player, start/end time, reminder state). Queried via `LiveGameState.Turns`.
- `live_game_state_view_screens` — append-only snapshots of scraped view screen data.
- `live_game_state_history_responses` — append-only snapshots of History API responses.
- `turn_history` — legacy append-only log of completed turns; used for round counting.
- `game_deaths` — one row per eliminated player per game; `inferred: true` for fog-of-war inference.
- `game_log_snapshots` — raw HTML log fetched from wargear.net.
- `game_log_events` — structured events parsed from snapshots (upserted by `game_id` + `log_seq`).
- `game_map_images` — board image binary stored per game; served at `GET /games/:game_id/map`.
- `message_templates` — editable Slack message templates.
- `settings` — key/value store (e.g. `wargear_cookie`, `wargear_api_key`). Accessed via `Spitegear.Settings.get/put`.

**Web routes:**

Public (no auth):
- `GET /` — landing page
- `GET /games` — live game index
- `GET /games/:game_id` — public game detail
- `GET /games/:game_id/map` — board image

Admin (HTTP Basic Auth against `users` table):
- `GET /admin` — admin home
- `GET /admin/games` — game list with controls
- `GET /admin/games/:game_id` — game detail + poller controls
- `GET /admin/games/:game_id/log` — game log events viewer
- `GET /admin/logs` — server logs
- `GET /admin/templates` and `/admin/games/:game_id/templates` — message template editor

API:
- `POST /api/slack/events` — Slack event webhook
- `POST /api/sleeper/draftpick` — Sleeper fantasy draft pick webhook

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

Deployed on a self-hosted server via GitHub Actions (`.github/workflows/deploy.yml`). The deploy job runs on a `self-hosted` runner, writes secrets to `$HOME/spitegear/.env`, pulls the latest code, then runs `make deploy` (builds a Docker image and restarts the container with `--env-file`). Assets built with `mix assets.deploy`.

To run commands on the deployed app:
```bash
ssh <server> "docker exec spitegear bin/spitegear rpc 'IO.inspect(SomeModule.some_function())'"
```
