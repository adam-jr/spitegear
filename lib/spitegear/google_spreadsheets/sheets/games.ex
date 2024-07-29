defmodule Spitegear.GoogleSpreadsheets.Sheets.Games do
  defmodule Row do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:game_id, :string)
      field(:url, :string)
      field(:game_name, :string)
      field(:board_name, :string)
      field(:created, :string)
      field(:finished, :string)
      field(:winners, {:array, :string})
    end

    def from_row(row) do
      %__MODULE__{
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

  def from_data([_headers | rest]), do: Enum.map(rest, &__MODULE__.Row.from_row/1)
end
