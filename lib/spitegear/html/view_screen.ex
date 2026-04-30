defmodule Spitegear.HTML.ViewScreen do
  defstruct game_id: nil,
            url: nil,
            game_name: nil,
            board_name: nil,
            created: nil,
            finished: nil,
            next_card: nil,
            players: [],
            current_player: nil,
            eliminated: [],
            winners: []

  def get_game(game_id) do
    with base_url <- URI.parse("https://www.wargear.net"),
         url <- %{base_url | path: "/games/view/#{game_id}"},
         {:ok, %{body: body}} <- HTTPoison.get(url, [{"Cookie", wargear_cookie()}]),
         {:ok, document} <- Floki.parse_document(body),
         {:ok, card} <- get_next_card(document),
         {:ok, game_name} <- game_name(document),
         {:ok, board_name} <- board_name(document),
         {:ok, created} <- created_time(document),
         {:ok, finished} <- finished_time(document),
         {:ok, player_table_rows} <- get_players(document),
         players <- Enum.map(player_table_rows, &Spitegear.HTML.Player.from_table_row/1) do
      {:ok,
       %__MODULE__{
         game_id: game_id,
         url: url,
         game_name: game_name,
         board_name: board_name,
         created: created,
         finished: finished,
         next_card: card,
         players: players,
         current_player: Enum.find(players, & &1.current_turn?),
         eliminated: Enum.filter(players, & &1.eliminated?),
         winners: Enum.filter(players, & &1.winner?)
       }}
    else
      _ ->
        :error
    end
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
    card_trs = [
      Floki.find(document, "tr:nth-child(15)"),
      Floki.find(document, "tr:nth-child(14)")
    ]

    case Enum.map(card_trs, &get_card_amount/1) do
      [:error, :error] -> {:ok, nil}
      [{:ok, amount}, :error] -> {:ok, amount}
      [:error, {:ok, amount}] -> {:ok, amount}
    end
  end

  def get_card_amount([tr]) do
    with {"tr", [], tds} <- tr,
         [_tile, amounts] <- tds,
         {"td", [], details} <- amounts,
         [{"font", _color, [{"b", [], [amount]}]}, _rest] <- details do
      {:ok, amount}
    else
      _ -> :error
    end
  end

  def get_card_amount(_), do: :error

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

  defp wargear_cookie do
    Application.get_env(:spitegear, Spitegear.Wargear.API)[:cookie] || ""
  end
end
