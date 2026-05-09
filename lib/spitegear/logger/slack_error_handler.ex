defmodule Spitegear.Logger.SlackErrorHandler do
  @moduledoc false

  # Erlang :logger handler — posts :error and above to #spitegear-alerts.
  # Registered in Application.start/2 after the supervision tree is up.

  alias Spitegear.Slack.API

  def log(%{level: level, msg: msg}, _config) when level in [:error, :critical, :alert, :emergency] do
    channel_id =
      Application.get_env(:spitegear, API, [])
      |> Keyword.get(:channel_ids, [])
      |> Keyword.get(:spitegear_alerts)

    if channel_id do
      text = format(msg)

      spawn(fn ->
        try do
          API.post_message(":rotating_light: [#{level}] #{text}", :spitegear_alerts)
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end
      end)
    end

    :ok
  end

  def log(_event, _config), do: :ok

  defp format({:string, msg}), do: IO.iodata_to_binary(msg)
  defp format({:report, report}), do: inspect(report)

  defp format({format, args}) when is_list(args) do
    :io_lib.format(format, args) |> IO.iodata_to_binary()
  end

  defp format(msg), do: inspect(msg)
end
