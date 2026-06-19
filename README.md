# Spitegear

A Phoenix/Elixir bot that monitors board games on [wargear.net](https://wargear.net) and sends Slack notifications. Tracks turn changes, player eliminations, winners, and sends reminder messages during waking hours.

## What it does

- Polls each active wargear.net game every 20 seconds (cheap history check) and fetches the full game screen only when a new turn is detected
- Announces turn changes, eliminations, and winners to Slack
- Sends reminder messages every 3 hours (waking hours, America/Chicago) when no turn has occurred
- Tracks round boundaries and posts round-complete announcements and turn stats
- Refreshes the wargear.net session cookie on a biweekly cron schedule
- Exposes an admin UI at `/admin` and a public game view with map images

## Stack

- Elixir / Phoenix 1.8, LiveView, Bandit
- PostgreSQL (Ecto)
- Slack Web API
- Docker + GitHub Actions (self-hosted runner)

## Development

```bash
mix setup              # install deps, create DB, build assets
mix phx.server         # start server at localhost:4001
iex -S mix phx.server  # start with interactive shell
mix test               # run all tests
mix credo              # lint (CI enforces --strict)
mix format             # format code
mix spitegear.create_user <username> <password>  # create an admin user
```

Local secrets go in `config/dev.secret.exs` (gitignored). Slack posting is disabled in dev via `config :spitegear, :post_to_slack, false`.

## Environment variables

| Variable | Purpose |
|---|---|
| `SLACK_AUTH_TOKEN` | Slack API calls |
| `DATABASE_URL` | Postgres connection (`ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Phoenix endpoint (generate with `mix phx.gen.secret`) |
| `PHX_HOST` / `PORT` | Phoenix endpoint host and port |
| `WARGEAR_USERNAME` | wargear.net login for cookie refresh |
| `WARGEAR_PASSWORD` | wargear.net login for cookie refresh |

`wargear_api_key` is stored in the `settings` DB table (not an env var) and must be set manually.

## Architecture

**Startup** (`application.ex`): `GameSupervisor` (DynamicSupervisor) spawns one `GamePoller` GenServer per active game on boot via `Games.resume_games/0`.

**Polling** (`Worker.GamePoller`): Two-layer — polls `Wargear.History` (REST) every 20 s for cheap turn-change detection; fetches the full `Wargear.HTML.ViewScreen` scrape only on a new `turnid` or within 10 minutes of a turn change (1-minute polls). Stops itself on game completion.

**Round tracking** (`Games.completed_rounds/1`): Walks `turn_history` chronologically, detects round boundaries when a player reappears. Posts round-complete announcements to `#spitegear`; posts turn stats every 5 rounds to `#spitegear_test`.

**Cookie management** (`Wargear.Login`): Biweekly Quantum cron job refreshes the session cookie stored in the `settings` table. `ViewScreen.get_game` auto-recovers from expired sessions with one retry.

**Slack** (`Spitegear.PubSub` → `Worker.SlackMessenger`): Incoming Slack events at `POST /api/slack/events` — a wargear.net game URL triggers a new `GamePoller`. Outbound messages flow through PubSub.

**DB tables**: `games`, `turns` (current turn, upserted), `turn_history` (append-only), `game_deaths`, `settings`.

## Deployment

Deployed via GitHub Actions on a self-hosted runner. The deploy job builds a Docker image and restarts the container with secrets injected via env file.
