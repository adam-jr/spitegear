defmodule Spitegear.Slack.API do
  @moduledoc false
  @bot_name "General Patton"

  def post_message(text, channel \\ :spitegear) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)

    url = %{config[:url] | path: config[:endpoints][:post_message]}

    body =
      %{text: text, channel: channel_id(channel), username: @bot_name}
      |> Jason.encode!()

    HTTPoison.post(url, body, headers())
  end

  def post_blocks(blocks, fallback_text, channel \\ :spitegear) do
    config = Application.get_env(:spitegear, __MODULE__)
    url = %{config[:url] | path: config[:endpoints][:post_message]}

    body =
      %{channel: channel_id(channel), blocks: blocks, text: fallback_text, username: @bot_name}
      |> Jason.encode!()

    HTTPoison.post(url, body, headers())
  end

  def post_dm(text, recipient) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)

    url = %{config[:url] | path: config[:endpoints][:post_message]}
    headers = headers()

    body =
      %{text: text}
      |> Map.put(:channel, dm_id(recipient))
      |> Jason.encode!()

    HTTPoison.post(url, body, headers)
  end

  @doc """
  Uploads a binary file to a Slack channel.
  `png_bytes` is the raw file content; `filename` is the display name.
  Returns `{:ok, response}` or `{:error, reason}`.
  """
  def upload_file(png_bytes, filename, channel) do
    config = Application.get_env(:spitegear, __MODULE__)
    url = %{config[:url] | path: "/api/files.upload"}

    body = {
      :multipart,
      [
        {"channels", channel_id(channel)},
        {"filename", filename},
        {"filetype", "png"},
        {"file", png_bytes, {"form-data", [{"name", "file"}, {"filename", filename}]},
         [{"Content-Type", "image/png"}]}
      ]
    }

    case HTTPoison.post(url, body, [{"Authorization", "Bearer #{auth_token()}"}],
           recv_timeout: 20_000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true}} -> :ok
          {:ok, %{"ok" => false, "error" => err}} -> {:error, err}
          _ -> {:error, "unexpected response"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "Slack returned HTTP #{code}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def new_messages(channel, timestamp \\ nil)

  def new_messages(channel, nil) do
    HTTPoison.get(url(:read_channel), headers(), params: %{channel: channel_id(channel)})
  end

  def new_messages(channel, timestamp) do
    HTTPoison.get(url(:read_channel), headers(),
      params: %{channel: channel_id(channel), oldest: timestamp}
    )
  end

  defp channel_id(channel) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)
    config[:channel_ids][channel]
  end

  defp dm_id(recipient) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)
    config[:dm_ids][recipient]
  end

  defp url(endpoint) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)
    %{config[:url] | path: config[:endpoints][endpoint]}
  end

  defp headers do
    [{"Content-Type", "application/json"}, {"Authorization", "Bearer #{auth_token()}"}]
  end

  defp auth_token do
    {:ok, auth_token} = System.fetch_env("SLACK_AUTH_TOKEN")
    auth_token
  end
end
