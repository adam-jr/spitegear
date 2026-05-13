defmodule Spitegear.Slack.API do
  @moduledoc false
  def post_message(text, channel \\ :spitegear) do
    config = Application.get_env(:spitegear, Spitegear.Slack.API)

    url = %{config[:url] | path: config[:endpoints][:post_message]}
    headers = headers()

    body =
      %{text: text}
      |> Map.put(:channel, channel_id(channel))
      |> Jason.encode!()

    HTTPoison.post(url, body, headers)
  end

  def post_blocks(blocks, fallback_text, channel \\ :spitegear) do
    config = Application.get_env(:spitegear, API)
    url = %{config[:url] | path: config[:endpoints][:post_message]}

    body =
      %{channel: channel_id(channel), blocks: blocks, text: fallback_text}
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
