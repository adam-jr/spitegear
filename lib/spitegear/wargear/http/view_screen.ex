defmodule Spitegear.Wargear.HTTP.ViewScreen do
  @moduledoc false
  require Logger

  alias Spitegear.HTML.Player
  alias Spitegear.Wargear.HTTP.Login

  @type t :: %__MODULE__{}

  defstruct game_id: nil,
            url: nil,
            game_name: nil,
            board_name: nil,
            created: nil,
            finished: nil,
            next_card: nil,
            map_image_url: nil,
            board_image_url: nil,
            players: [],
            current_player: nil,
            eliminated: [],
            winners: [],
            fogged?: false

  def get_game(game_id), do: fetch_game(game_id, false)

  defp fetch_game(game_id, retried) do
    url_string = "https://www.wargear.net/games/view/#{game_id}"
    url = URI.parse(url_string)

    with {:ok, %{body: body}} <-
           HTTPoison.get(url_string, [{"Cookie", wargear_cookie()}],
             timeout: 30_000,
             recv_timeout: 30_000
           ),
         :ok <- check_session(body),
         {:ok, document} <- Floki.parse_document(body),
         {:ok, card} <- get_next_card(document),
         {:ok, game_name} <- game_name(document),
         {:ok, board_name} <- board_name(document),
         {:ok, created} <- created_time(document),
         {:ok, finished} <- finished_time(document),
         {:ok, player_table_rows} <- get_players(document),
         players <-
           player_table_rows
           |> Enum.with_index(1)
           |> Enum.map(fn {row, seat} -> %{Player.from_table_row(row) | seat_number: seat} end) do
      {:ok,
       %__MODULE__{
         game_id: game_id,
         url: url,
         game_name: game_name,
         board_name: board_name,
         created: created,
         finished: finished,
         next_card: card,
         map_image_url: map_image_url(document),
         board_image_url: board_image_url(document, game_id),
         players: players,
         current_player: Enum.find(players, & &1.current_turn?),
         eliminated: Enum.filter(players, & &1.eliminated?),
         winners: Enum.filter(players, & &1.winner?),
         fogged?: Enum.any?(players, & &1.fogged?)
       }}
    else
      :session_expired when not retried ->
        Logger.info("#{__MODULE__} session expired, refreshing cookie and retrying")
        Login.refresh_cookie()
        fetch_game(game_id, true)

      _ ->
        :error
    end
  end

  defp check_session(body) do
    if String.contains?(body, "login_required=1"), do: :session_expired, else: :ok
  end

  def created_time(document) do
    document
    |> Floki.find("table.ranking.data tr")
    |> Enum.find(fn row ->
      Floki.text(Floki.find(row, "td:first-child")) == "Created"
    end)
    |> case do
      nil -> {:ok, nil}
      row -> {:ok, Floki.text(Floki.find(row, "td span.small"))}
    end
  end

  def finished_time(document) do
    document
    |> Floki.find("table.ranking.data tr")
    |> Enum.find(fn row ->
      Floki.text(Floki.find(row, "td:first-child")) == "Finished"
    end)
    |> case do
      nil -> {:ok, nil}
      row -> {:ok, Floki.text(Floki.find(row, "td span.small"))}
    end
  end

  def board_name(document) do
    document
    |> Floki.find("table.ranking.data tr")
    |> Enum.find(fn row ->
      Floki.text(Floki.find(row, "td:first-child")) == "Board Name"
    end)
    |> case do
      nil -> {:ok, nil}
      row -> {:ok, Floki.text(Floki.find(row, "td a.dotted:first-child"))}
    end
  end

  def game_name(document) do
    document
    |> Floki.find("div#breadcrumbs > a:nth-child(3)")
    |> get_game_name()
  end

  def get_game_name(names) do
    with [name | _rest] <- names,
         {_, _, name} <- name,
         [str] when is_binary(str) <- name do
      {:ok, String.trim(str)}
    else
      _ -> :error
    end
  end

  def get_next_card(document) do
    amount =
      document
      |> Floki.find("tr")
      |> Enum.find_value(fn
        {_, _, [label_td, {_, _, [{"font", _color, [{"b", [], [amount]}]} | _]} | _]} ->
          if String.trim(Floki.text(label_td)) == "Next Card Set Worth", do: amount

        _ ->
          nil
      end)

    {:ok, amount}
  end

  def get_players(document) do
    document
    |> Floki.find("div#playerstats")
    |> get_player_rows()
  end

  def get_player_rows([div]) do
    with {"div", [{"id", "playerstats"}], table} <- div,
         [{"table", [{"class", "data ranking centered"}], tbody}] <- table,
         [{"tbody", [], [_hd | player_rows]}] <- tbody do
      {:ok, player_rows}
    else
      _ -> :error
    end
  end

  def get_player_rows(_), do: :error

  # Selector may need tuning after inspecting live wargear.net HTML.
  defp map_image_url(document) do
    document
    |> Floki.find("img[src*='/boards/']")
    |> List.first()
    |> case do
      nil ->
        document
        |> Floki.find("img[src*='/games/images/']")
        |> List.first()

      img ->
        img
    end
    |> case do
      nil -> nil
      {"img", attrs, _} -> resolve_url(List.keyfind(attrs, "src", 0))
    end
  end

  @board_image_width 2400
  @board_image_height 2000

  defp board_image_url(document, _game_id) do
    document
    |> Floki.find("img[src*='GetBoardImage']")
    |> List.first()
    |> case do
      nil ->
        nil

      {"img", attrs, _} ->
        attrs
        |> List.keyfind("src", 0)
        |> resolve_url()
        |> with_hires_size()
    end
  end

  defp with_hires_size(nil), do: nil

  defp with_hires_size(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")

    new_query =
      query
      |> Map.put("width", @board_image_width)
      |> Map.put("height", @board_image_height)
      |> URI.encode_query()

    URI.to_string(%{uri | query: new_query})
  end

  defp resolve_url(nil), do: nil
  defp resolve_url({"src", "/" <> _ = path}), do: "https://www.wargear.net#{path}"
  defp resolve_url({"src", "http" <> _ = url}), do: url
  defp resolve_url(_), do: nil

  defp wargear_cookie do
    Spitegear.Settings.get("wargear_cookie") ||
      Application.get_env(:spitegear, Spitegear.Wargear.API)[:cookie] || ""
  end
end
