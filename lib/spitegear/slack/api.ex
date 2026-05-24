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
  Uploads a binary file to a Slack channel using the v2 upload API
  (files.getUploadURLExternal → PUT → files.completeUploadExternal).
  `png_bytes` is the raw file content; `filename` is the display name.
  Returns `:ok` or `{:error, reason}`.
  """
  def upload_file(png_bytes, filename, channel) do
    config = Application.get_env(:spitegear, __MODULE__)
    base_url = config[:url]
    auth = [{"Authorization", "Bearer #{auth_token()}"}]

    with {:ok, %{"upload_url" => upload_url, "file_id" => file_id}} <-
           get_upload_url(base_url, filename, byte_size(png_bytes), auth),
         :ok <- put_file(upload_url, png_bytes) do
      complete_upload(base_url, file_id, filename, channel_id(channel), auth)
    end
  end

  defp get_upload_url(base_url, filename, length, auth) do
    url = %{base_url | path: "/api/files.getUploadURLExternal"}
    params = [filename: filename, length: length]

    case HTTPoison.get(url, auth, params: params, recv_timeout: 15_000) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true} = resp} -> {:ok, resp}
          {:ok, %{"ok" => false, "error" => err}} -> {:error, err}
          _ -> {:error, "unexpected response from getUploadURLExternal"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "Slack returned HTTP #{code} on getUploadURLExternal"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp put_file(upload_url, png_bytes) do
    case HTTPoison.put(upload_url, png_bytes, [{"Content-Type", "image/png"}],
           recv_timeout: 20_000
         ) do
      {:ok, %{status_code: code}} when code in 200..299 -> :ok
      {:ok, %{status_code: code}} -> {:error, "upload PUT returned HTTP #{code}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp complete_upload(base_url, file_id, title, channel_id, auth) do
    url = %{base_url | path: "/api/files.completeUploadExternal"}

    body =
      Jason.encode!(%{
        files: [%{id: file_id, title: title}],
        channel_id: channel_id
      })

    case HTTPoison.post(url, body, [{"Content-Type", "application/json"} | auth],
           recv_timeout: 15_000
         ) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode(resp_body) do
          {:ok, %{"ok" => true}} -> :ok
          {:ok, %{"ok" => false, "error" => err}} -> {:error, err}
          _ -> {:error, "unexpected response from completeUploadExternal"}
        end

      {:ok, %{status_code: code}} ->
        {:error, "Slack returned HTTP #{code} on completeUploadExternal"}

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
