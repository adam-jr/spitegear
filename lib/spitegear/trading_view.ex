defmodule Spitegear.TradingView do
  def coin_breadth(columns) do
    coins = get_coins(columns)

    if is_list(coins) do
      adv = Enum.filter(coins, fn {_coin, _close, delta} -> delta > 0 end) |> Enum.count()
      dec = Enum.filter(coins, fn {_coin, _close, delta} -> delta < 0 end) |> Enum.count()
      {:ok, {adv, dec}}
    else
      :error
    end
  end

  def current_price(sym) do
    url = URI.parse("https://min-api.cryptocompare.com/data/price?fsym=#{sym}&tsyms=USD")

    with {:ok, res} <- HTTPoison.get(url),
         {:ok, %{"USD" => price_usd}} <- Jason.decode(res.body) do
      {:ok, price_usd}
    else
      _ ->
        :error
    end
  end

  defp get_coins(columns) do
    with %{body: body} <- top_750_coins(columns),
         {:ok, %{data: coins}} <- Jason.decode(body, keys: :atoms) do
      coins
      |> Enum.reject(&stablecoin?/1)
      |> Enum.map(fn %{d: [close, pct_delta_24h, _categories], s: coin} ->
        {coin, close, pct_delta_24h}
      end)
    else
      _e ->
        :error
    end
  end

  defp stablecoin?(%{d: [_close, _pct, categories]}) when is_list(categories),
    do: "stablecoins" in categories

  defp stablecoin?(_d), do: false

  defp top_750_coins(columns) do
    config = Application.get_env(:spitegear, Spitegear.TradingView.API)

    url = %{config[:url] | path: config[:endpoints][:crypto_coins]}
    headers = []

    body =
      %{
        "columns" => columns,
        "ignore_unknown_fields" => false,
        "preset" => "coin_market_cap_rank",
        "range" => [0, 750],
        "sort" => %{
          "nullsFirst" => false,
          "sortBy" => "crypto_total_rank",
          "sortOrder" => "asc"
        }
      }
      |> Jason.encode!()

    HTTPoison.post!(url, body, headers)
  end
end
