defmodule Spitegear.Slack.API do
  @moduledoc false
  @bot_name "General Patton"

  def post_message(text, channel \\ :spitegear) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)
    %URI{} = base = config[:url]
    url = %{base | path: config[:endpoints][:post_message]} |> URI.to_string()

    body =
      %{text: text, channel: channel_id(channel), username: @bot_name}
      |> Jason.encode!()

    Req.post(url, body: body, headers: headers())
  end

  def post_blocks(blocks, fallback_text, channel \\ :spitegear) do
    config = Application.get_env(:spitegear, __MODULE__)
    %URI{} = base = config[:url]
    url = %{base | path: config[:endpoints][:post_message]} |> URI.to_string()

    body =
      %{channel: channel_id(channel), blocks: blocks, text: fallback_text, username: @bot_name}
      |> Jason.encode!()

    Req.post(url, body: body, headers: headers())
  end

  def post_dm(text, recipient) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)

    %URI{} = base = config[:url]
    url = %{base | path: config[:endpoints][:post_message]} |> URI.to_string()

    body =
      %{text: text}
      |> Map.put(:channel, dm_id(recipient))
      |> Jason.encode!()

    Req.post(url, body: body, headers: headers())
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
    %URI{} = base_url
    url = %{base_url | path: "/api/files.getUploadURLExternal"} |> URI.to_string()
    params = [filename: filename, length: length]

    case Req.get(url, headers: auth, params: params, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"ok" => true} = resp}} ->
        {:ok, resp}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => err}}} ->
        {:error, err}

      {:ok, %{status: 200}} ->
        {:error, "unexpected response from getUploadURLExternal"}

      {:ok, %{status: code}} ->
        {:error, "Slack returned HTTP #{code} on getUploadURLExternal"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp put_file(upload_url, png_bytes) do
    case Req.put(upload_url, body: png_bytes, headers: [{"Content-Type", "image/png"}], receive_timeout: 20_000, decode_body: false) do
      {:ok, %{status: code}} when code in 200..299 -> :ok
      {:ok, %{status: code}} -> {:error, "upload PUT returned HTTP #{code}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp complete_upload(base_url, file_id, title, channel_id, auth) do
    %URI{} = base_url
    url = %{base_url | path: "/api/files.completeUploadExternal"} |> URI.to_string()

    body =
      Jason.encode!(%{
        files: [%{id: file_id, title: title}],
        channel_id: channel_id
      })

    case Req.post(url, body: body, headers: [{"Content-Type", "application/json"} | auth], receive_timeout: 15_000) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"ok" => false, "error" => err}}} ->
        {:error, err}

      {:ok, %{status: 200}} ->
        {:error, "unexpected response from completeUploadExternal"}

      {:ok, %{status: code}} ->
        {:error, "Slack returned HTTP #{code} on completeUploadExternal"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def new_messages(channel, timestamp \\ nil)

  def new_messages(channel, nil) do
    Req.get(url(:read_channel), headers: headers(), params: %{channel: channel_id(channel)})
  end

  def new_messages(channel, timestamp) do
    Req.get(url(:read_channel),
      headers: headers(),
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
    %URI{} = base = config[:url]
    %{base | path: config[:endpoints][endpoint]} |> URI.to_string()
  end

  defp headers do
    [{"Content-Type", "application/json"}, {"Authorization", "Bearer #{auth_token()}"}]
  end

  defp auth_token do
    {:ok, auth_token} = System.fetch_env("SLACK_AUTH_TOKEN")
    auth_token
  end
end
