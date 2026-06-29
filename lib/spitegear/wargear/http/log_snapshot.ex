defmodule Spitegear.Wargear.HTTP.LogSnapshot do
  @moduledoc """
  Fetches and stores the raw HTML game log from wargear.net for a completed game.

  The log page at /games/log/:id contains the full play-by-play history.
  We snapshot it as raw HTML immediately when a game finishes so it can be
  parsed and mined later without depending on wargear.net staying up.
  """

  require Logger

  alias Spitegear.GameLogSnapshot
  alias Spitegear.Repo
  alias Spitegear.Settings
  alias Spitegear.Wargear.HTTP.Login

  @base_url "https://www.wargear.net"

  @doc """
  Fetches the game log HTML for `game_id` and inserts it into `game_log_snapshots`.

  Skips silently if a snapshot already exists for this game.
  Returns `{:ok, snapshot}` or `{:error, reason}`.
  """
  def capture(game_id) do
    Logger.info("#{__MODULE__} capturing log snapshot for game #{game_id}")

    with {:ok, html} <- fetch_log(game_id, false),
         {:ok, snapshot} <- insert_snapshot(game_id, html) do
      Logger.info(
        "#{__MODULE__} log snapshot saved for game #{game_id} (#{byte_size(html)} bytes)"
      )

      {:ok, snapshot}
    else
      {:error, reason} ->
        Logger.error(
          "#{__MODULE__} failed to capture log for game #{game_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Re-fetches the game log HTML and updates the stored snapshot.
  Unlike `capture/1`, this always overwrites an existing snapshot.
  Returns `{:ok, snapshot}` or `{:error, reason}`.
  """
  def refetch(game_id) do
    Logger.info("#{__MODULE__} re-fetching log snapshot for game #{game_id}")

    with {:ok, html} <- fetch_log(game_id, false),
         {:ok, snapshot} <- replace_snapshot(game_id, html) do
      Logger.info(
        "#{__MODULE__} log snapshot updated for game #{game_id} (#{byte_size(html)} bytes)"
      )

      {:ok, snapshot}
    else
      {:error, reason} ->
        Logger.error(
          "#{__MODULE__} failed to refetch log for game #{game_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp fetch_log(game_id, retried) do
    url = @base_url <> "/games/log/#{game_id}?showsetup=1&showips="

    case Req.get(url, headers: [{"Cookie", wargear_cookie()}], receive_timeout: 30_000, decode_body: false) do
      {:ok, %{body: body}} -> check_session(body, game_id, retried)
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_session(body, game_id, retried) do
    case login_required?(body) do
      true -> handle_expired_session(game_id, retried)
      false -> {:ok, body}
    end
  end

  defp handle_expired_session(_game_id, true), do: {:error, :login_required}

  defp handle_expired_session(game_id, false) do
    Logger.info("#{__MODULE__} session expired, refreshing cookie and retrying")
    Login.refresh_cookie()
    fetch_log(game_id, true)
  end

  defp insert_snapshot(game_id, html) do
    attrs = %{
      game_id: game_id,
      html: html,
      fetched_at: DateTime.utc_now()
    }

    changeset = GameLogSnapshot.changeset(%GameLogSnapshot{}, attrs)

    Repo.insert(changeset,
      on_conflict: :nothing,
      conflict_target: :game_id,
      returning: true
    )
  end

  defp replace_snapshot(game_id, html) do
    attrs = %{
      game_id: game_id,
      html: html,
      fetched_at: DateTime.utc_now()
    }

    changeset = GameLogSnapshot.changeset(%GameLogSnapshot{}, attrs)

    Repo.insert(changeset,
      on_conflict: {:replace, [:html, :fetched_at, :updated_at]},
      conflict_target: :game_id,
      returning: true
    )
  end

  defp login_required?(body), do: String.contains?(body, "login_required=1")

  defp wargear_cookie, do: Settings.get("wargear_cookie")
end
