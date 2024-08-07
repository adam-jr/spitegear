defmodule Spitegear.Worker.CryptoBreadthPoller do
  @moduledoc """
  get da coins
  """

  def perform do
    freq = :daily

    columns =
      case freq do
        :hourly ->
          ["close", "change|60", "crypto_common_categories"]

        :daily ->
          ["close", "24h_close_change|5", "crypto_common_categories"]
      end

    with {:ok, {adv, dec}} <- Spitegear.TradingView.coin_breadth(columns),
         {:ok, btc} <- Spitegear.TradingView.current_price("BTC"),
         {:ok, eth} <- Spitegear.TradingView.current_price("ETH") do
      write_to_sheet(adv, dec, btc, eth, :daily)
    end
  end

  @daily_sheet_id "1JY4KiKiLNteTawg2Me-S6U7po36CGaPnl9b_7v-tCxM"
  @sheet_name "2024"
  def write_to_sheet(adv, dec, btc, eth, :daily) do
    columns = build_columns(adv, dec, btc, eth)
    Spitegear.GoogleSpreadsheets.API.append_cells(@daily_sheet_id, @sheet_name, [columns])
  end

  def build_columns(adv, dec, btc, eth) do
    date = Date.utc_today() |> to_string()

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           Spitegear.GoogleSpreadsheets.API.get_individual_sheet(@daily_sheet_id, @sheet_name),
         {:ok, data} <- Jason.decode(body) do
      row = length(data["values"])
      [date, adv, dec, btc, eth] ++ daily_calculations(row + 1)
    end
  end

  defp daily_calculations(row) do
    [
      "=SUM(B#{row - 4}:B#{row})",
      "=SUM(C#{row - 4}:C#{row})",
      "=F#{row}/(G#{row}+F#{row})",
      "=B#{row}/(C#{row}+B#{row})",
      "=(D#{row}-D#{row - 1})/D#{row - 1}",
      "=(E#{row}-E#{row - 1})/E#{row - 1}"
    ]
  end
end
