defmodule Spitegear.GoogleSpreadsheets.Sheets.Games do
  alias Spitegear.GoogleSpreadsheets.API
  alias Spitegear.GoogleSpreadsheets

  def update_or_create_row(view_screen) do
    with {:ok, rows} <- GoogleSpreadsheets.Reader.fetch_sheet_data("games"),
         row_struct <- Enum.find(rows, &(&1.game_id == view_screen.game_id)) do
      index =
        if row_struct do
          row_struct.index
        else
          length(rows)
        end

      data = to_data(view_screen)
      res = API.update_cells(GoogleSpreadsheets.Reader.spreadsheet_id(), "games", range(index), [data])
      GoogleSpreadsheets.Reader.refresh_games()
      res
    end
  end

  defp to_data(view_screen) do
    [
      view_screen.game_id,
      URI.to_string(view_screen.url),
      view_screen.game_name,
      view_screen.board_name,
      view_screen.created,
      view_screen.finished,
      winner(view_screen, 0),
      winner(view_screen, 1),
      winner(view_screen, 2)
    ]
  end

  defp winner(vs, index) do
    w = Enum.at(vs.winners, index)
    w && w.name
  end

  def from_data([_headers | rest]) do
    Enum.with_index(rest) |> Enum.map(&__MODULE__.Row.from_row/1)
  end

  defp range(index) do
    i = index + 2
    "#{i}:#{i}"
  end

  defmodule Row do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:index, :integer)
      field(:game_id, :string)
      field(:url, :string)
      field(:game_name, :string)
      field(:board_name, :string)
      field(:created, :string)
      field(:finished, :string)
      field(:winners, {:array, :string})
    end

    def from_row({row, index}) do
      %__MODULE__{
        index: index,
        game_id: get_val(row, 0),
        url: get_val(row, 1),
        game_name: get_val(row, 2),
        board_name: get_val(row, 3),
        created: get_val(row, 4),
        finished: get_val(row, 5),
        winners: winners(row)
      }
    end

    defp get_val(row, index), do: val(Enum.at(row, index))

    defp val(""), do: nil
    defp val(str) when is_binary(str), do: str
    defp val(_), do: nil

    defp winners(row) do
      [
        get_val(row, 6),
        get_val(row, 7),
        get_val(row, 8)
      ]
      |> Enum.reject(&(&1 == nil))
    end
  end
end
