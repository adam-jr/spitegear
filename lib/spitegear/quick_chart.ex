defmodule Spitegear.QuickChart do
  @moduledoc """
  Renders Chart.js configs to PNG via the quickchart.io API.
  Returns raw PNG bytes suitable for uploading to Slack.
  """

  @url "https://quickchart.io/chart"
  @width 900
  @height 450

  @colors [
    "rgb(59,130,246)",
    "rgb(239,68,68)",
    "rgb(34,197,94)",
    "rgb(245,158,11)",
    "rgb(168,85,247)",
    "rgb(20,184,166)"
  ]

  @doc """
  Renders a net-units-over-time series to a PNG binary.
  `series` is the map returned by `GameLog.Stats.net_units_over_time/1`.
  Returns `{:ok, png_binary}` or `{:error, reason}`.
  """
  def render_net_units(series) do
    body =
      Jason.encode!(%{
        chart: build_config(series),
        width: @width,
        height: @height,
        backgroundColor: "white"
      })

    case Req.post(@url, body: body, headers: [{"Content-Type", "application/json"}], receive_timeout: 20_000, decode_body: false) do
      {:ok, %{status: 200, body: png}} -> {:ok, png}
      {:ok, %{status: code}} -> {:error, "QuickChart returned HTTP #{code}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp build_config(series) do
    datasets =
      series
      |> Enum.sort_by(fn {player, _} -> player end)
      |> Enum.with_index()
      |> Enum.map(fn {{player, points}, i} ->
        color = Enum.at(@colors, rem(i, length(@colors)))

        %{
          label: player,
          data: Enum.map(points, fn %{seq: s, net_units: n} -> %{x: s, y: n} end),
          borderColor: color,
          backgroundColor: color,
          fill: false,
          stepped: true,
          pointRadius: 2,
          borderWidth: 2
        }
      end)

    %{
      type: "line",
      data: %{datasets: datasets},
      options: %{
        scales: %{
          x: %{type: "linear", title: %{display: true, text: "Log Seq"}},
          y: %{title: %{display: true, text: "Net Units"}}
        },
        plugins: %{
          legend: %{position: "top"}
        }
      }
    }
  end
end
