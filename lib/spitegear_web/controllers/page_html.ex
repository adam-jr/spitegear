defmodule SpitegearWeb.PageHTML do
  use SpitegearWeb, :html

  embed_templates "page_html/*"

  def elapsed(nil), do: "—"

  def elapsed(started) do
    diff = DateTime.diff(DateTime.utc_now(), started)
    format_duration(diff)
  end

  defp format_duration(s) when s < 60, do: "#{s}s"
  defp format_duration(s) when s < 3600, do: "#{div(s, 60)}m"

  defp format_duration(s) do
    h = div(s, 3600)
    m = div(rem(s, 3600), 60)
    if m > 0, do: "#{h}h #{m}m", else: "#{h}h"
  end
end
