defmodule Spitegear.Wargear.HTTP.Proxy do
  @moduledoc """
  Optional HTTP forward-proxy for outbound wargear.net requests.

  Controlled at runtime via the `wargear_proxy_url` setting (e.g.
  `http://user:pass@host:port`), so it can be toggled without a redeploy —
  useful for routing around an IP-based rate limit or block. When the
  setting is absent or blank, requests go out directly.

  Only HTTP CONNECT-style forward proxies are supported (what Mint/Finch
  support natively) — e.g. Squid, tinyproxy, Privoxy, or most commercial
  HTTP proxy providers. A bare SOCKS5 endpoint (like Cloudflare WARP's
  proxy mode) needs an HTTP-to-SOCKS bridge such as Privoxy in front of it.
  """

  alias Spitegear.Settings

  @spec req_options() :: keyword()
  def req_options do
    case Settings.get("wargear_proxy_url") do
      url when is_binary(url) and url != "" -> options_for(url)
      _ -> []
    end
  end

  defp options_for(url) do
    uri = URI.parse(url)
    scheme = if uri.scheme == "https", do: :https, else: :http

    connect_options =
      [proxy: {scheme, uri.host, uri.port, []}] ++ proxy_headers(uri.userinfo)

    [connect_options: connect_options]
  end

  defp proxy_headers(nil), do: []

  defp proxy_headers(userinfo) do
    [proxy_headers: [{"proxy-authorization", "Basic " <> Base.encode64(userinfo)}]]
  end
end
