defmodule Spitegear.GoogleSpreadsheets.Sheets.Turns do
  alias Spitegear.GoogleSpreadsheets.API
  alias Spitegear.GoogleSpreadsheets

  defmodule Row do
    use Ecto.Schema
    require Logger

    @primary_key false
    embedded_schema do
      field(:index, :integer)
      field(:game_id, :string)
      field(:player, :any, virtual: true)
      field(:started, :string)
      field(:reminded, :string)
      field(:reminders, :integer, default: 0)
    end

    def from_row({row, index}) do
      %__MODULE__{
        index: index,
        game_id: get_val(row, 0),
        player: Spitegear.HTML.Player.from_name(get_val(row, 1)),
        started: datetime(get_val(row, 2)),
        reminded: datetime(get_val(row, 3)),
        reminders: get_val(row, 4)
      }
    end

    defp datetime(nil), do: nil

    defp datetime(str) do
      case DateTime.from_iso8601(str) do
        {:ok, datetime, _offset} ->
          datetime

        {:error, reason} ->
          Logger.error("failed to cast to DateTime: #{reason}")
          nil
      end
    end

    defp get_val(row, index), do: val(Enum.at(row, index))

    defp val(""), do: nil
    defp val(str) when is_binary(str), do: str
    defp val(_), do: nil
  end

  defp to_data(turn) do
    [
      turn.game_id,
      turn.player.name,
      turn.started,
      turn.reminded,
      turn.reminders
    ]
  end

  def update_or_create_row(%__MODULE__.Row{} = turn) do
    with {:ok, rows} <- GoogleSpreadsheets.Reader.get_sheet("turns"),
         row_struct <- Enum.find(rows, &(&1.game_id == turn.game_id)) do
      index =
        if row_struct do
          row_struct.index
        else
          length(rows)
        end

      data = to_data(turn)

      res =
        API.update_cells(GoogleSpreadsheets.Reader.spreadsheet_id(), "turns", range(index), [data])

      GoogleSpreadsheets.Reader.refresh_sheet(:turns)
      res
    end
  end

  def from_data([_headers | rest]) do
    Enum.with_index(rest) |> Enum.map(&__MODULE__.Row.from_row/1)
  end

  defp range(index) do
    i = index + 2
    "#{i}:#{i}"
  end
end
