defmodule Spitegear.Wargear.HTTP.Login do
  @moduledoc false
  require Logger

  alias Spitegear.Settings

  @base_url "https://www.wargear.net"

  def refresh_cookie do
    username = System.fetch_env!("WARGEAR_USERNAME")
    password = System.fetch_env!("WARGEAR_PASSWORD")

    case login(username, password) do
      {:ok, cookie} ->
        Settings.put("wargear_cookie", cookie)
        Logger.info("#{__MODULE__} cookie refreshed successfully")
        :ok

      {:error, reason} ->
        Logger.error("#{__MODULE__} cookie refresh failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def extract_cookie(headers) do
    headers
    |> Enum.filter(fn {name, _} -> String.downcase(name) == "set-cookie" end)
    |> Enum.map_join("; ", fn {_, value} ->
      value |> String.split(";") |> List.first() |> String.trim()
    end)
  end

  defp login(username, password) do
    body =
      URI.encode_query(%{
        "username" => username,
        "password" => password,
        "cookie_setting" => "autologin",
        "loginbtn" => "loginbtn",
        "uid" => ""
      })

    with {:ok, initial_cookies} <- get_initial_cookies(),
         headers = [
           {"Content-Type", "application/x-www-form-urlencoded"},
           {"Cookie", initial_cookies}
         ],
         {:ok, %{headers: resp_headers}} <-
           Req.post(@base_url <> "/player/login", body: body, headers: headers, redirect: false),
         cookie when cookie != "" <- extract_cookie(resp_headers) do
      {:ok, cookie}
    else
      "" -> {:error, :no_cookie_in_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_initial_cookies do
    case Req.get(@base_url <> "/player/login", receive_timeout: 15_000) do
      {:ok, %{headers: headers}} -> {:ok, extract_cookie(headers)}
      {:error, reason} -> {:error, reason}
    end
  end
end
