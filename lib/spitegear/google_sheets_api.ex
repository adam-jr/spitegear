defmodule Spitegear.GoogleSheets.API do
  def get_values(spreadsheet_id, sheet_name) do
    _ = Finch.start_link(name: :google_spreadsheets)

    url =
      URI.encode(
        "https://sheets.googleapis.com/v4/spreadsheets/#{spreadsheet_id}/values/#{sheet_name}"
      )

    Finch.build(:get, url, headers())
    |> Finch.request(:google_spreadsheets)
  end

  def append_cells(spreadsheet_id, sheet_name, data) do
    _ = Finch.start_link(name: :google_spreadsheets)

    url =
      URI.encode(
        "https://sheets.googleapis.com/v4/spreadsheets/#{spreadsheet_id}/values/#{sheet_name}:append?valueInputOption=USER_ENTERED"
      )

    body = Jason.encode!(%{"values" => [data]})

    Finch.build(:post, url, headers(), body)
    |> Finch.request(:google_spreadsheets)
  end

  def update_cells(spreadsheet_id, sheet_name, range, data) do
    _ = Finch.start_link(name: :google_spreadsheets)

    url =
      URI.encode(
        "https://sheets.googleapis.com/v4/spreadsheets/#{spreadsheet_id}/values/#{sheet_name}!#{range}?valueInputOption=USER_ENTERED"
      )

    body = Jason.encode!(%{"values" => data})

    Finch.build(:put, url, headers(), body)
    |> Finch.request(:google_spreadsheets)
  end

  def delete_row(spreadsheet_id, sheet_id, row_index) do
    _ = Finch.start_link(name: :google_spreadsheets)

    url =
      URI.encode("https://sheets.googleapis.com/v4/spreadsheets/#{spreadsheet_id}:batchUpdate")

    body =
      Jason.encode!(%{
        "requests" => [
          %{
            "deleteDimension" => %{
              "range" => %{
                "sheetId" => sheet_id,
                "dimension" => "ROWS",
                "startIndex" => row_index,
                "endIndex" => row_index + 1
              }
            }
          }
        ]
      })

    Finch.build(:post, url, headers(), body)
    |> Finch.request(:google_spreadsheets)
  end

  defp headers,
    do: [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{GSS.Registry.token()}"}
    ]
end
