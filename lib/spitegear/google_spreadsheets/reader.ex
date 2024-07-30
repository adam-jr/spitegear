defmodule Spitegear.GoogleSpreadsheets.Reader do
  use GenServer

  require Logger

  alias Spitegear.GoogleSpreadsheets.API
  alias Spitegear.GoogleSpreadsheets.Sheets

  @spreadsheet_id "1qhTcmKRpnmknMV3opGv1jdpQ1d6hFCU862lIRy1jL-Q"

  def spreadsheet_id, do: @spreadsheet_id

  # Public API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_row(sheet_name, game_id) do
    case get_sheet(sheet_name) do
      {:ok, rows} ->
        Enum.find(rows, fn row -> row.game_id == game_id end)

      _ ->
        nil
    end
  end

  def get_sheet(sheet_name) do
    GenServer.call(__MODULE__, {:get_sheet, sheet_name})
  end

  def refresh_sheet(sheet_name) do
    GenServer.call(__MODULE__, {:refresh, sheet_name})
  end

  def start_games do
    send(__MODULE__, :start_games)
  end

  # Callbacks
  @impl true
  def init(_opts) do
    schedule_retry(0)
    {:ok, %{retry_count: 0, sheets: [], current_sheet: nil, data: %{}, loading: true}}
  end

  @impl true
  def handle_call({:get_sheet, sheet_name}, from, %{loading: true} = state) do
    Process.send_after(self(), {:get_sheet, sheet_name, from}, 1000)
    {:noreply, state}
  end

  def handle_call({:get_sheet, sheet_name}, _from, state) do
    case get_in(state, [:data, to_string(sheet_name)]) do
      nil ->
        {:reply, :error, state}

      data ->
        {:reply, {:ok, data}, state}
    end
  end

  def handle_call({:refresh, sheet_name}, _from, state) do
    sheet_name = to_string(sheet_name)

    case load_individual_sheet(sheet_name) do
      {:ok, data} ->
        {:reply, {:ok, data},
         %{
           state
           | data: Map.put(state.data, sheet_name, parse_sheet(sheet_name, data))
         }}

      :error ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_info({:get_sheet, sheet_name, from}, state) do
    if state.loading do
      Process.send_after(self(), {:get_sheet, sheet_name, from}, 1000)
    else
      data = get_in(state, [:data, to_string(sheet_name)])
      GenServer.reply(from, {:ok, data})
    end

    {:noreply, state}
  end

  def handle_info(:load_google_sheet, %{retry_count: retry_count} = state) do
    Logger.info("Started loading sheets")

    case load_spreadsheet() do
      {:ok, sheets} ->
        schedule_sheet_processing()
        {:noreply, %{state | retry_count: 0, sheets: sheets}}

      :error ->
        new_retry_count = retry_count + 1
        schedule_retry(new_retry_count)
        {:noreply, %{state | retry_count: new_retry_count}}
    end
  end

  @impl true
  def handle_info(:process_next_sheet, %{sheets: [current_sheet | remaining_sheets]} = state) do
    case load_individual_sheet(current_sheet) do
      {:ok, data} ->
        schedule_sheet_processing()

        {:noreply,
         %{
           state
           | sheets: remaining_sheets,
             current_sheet: current_sheet,
             data: Map.put(state.data, current_sheet, parse_sheet(current_sheet, data))
         }}

      :error ->
        schedule_sheet_processing()
        {:noreply, %{state | sheets: remaining_sheets, current_sheet: current_sheet}}
    end
  end

  @impl true
  def handle_info(:process_next_sheet, %{sheets: []} = state) do
    Logger.info("Finished loading sheets!")
    resume_games(state.data["games"])
    {:noreply, %{state | loading: false}}
  end

  @sheets [
    games: Sheets.Games,
    turns: Sheets.Turns
  ]
  defp parse_sheet(sheet_name, %{"values" => values}) do
    case Keyword.get(@sheets, String.to_atom(sheet_name)) do
      nil ->
        []

      module ->
        module.from_data(values)
    end
  end

  defp resume_games(games) do
    Enum.each(games, fn game ->
      if is_nil(game.finished) do
        DynamicSupervisor.start_child(
          GameSupervisor,
          Spitegear.Worker.GamePoller.child_spec(game_id: game.game_id)
        )
      end
    end)
  end

  defp schedule_retry(retry_count) do
    delay = (:math.pow(2, retry_count) * 1_000) |> round()
    Process.send_after(self(), :load_google_sheet, delay)
  end

  defp schedule_sheet_processing do
    # Process each sheet after a delay
    Process.send_after(self(), :process_next_sheet, 200)
  end

  defp load_spreadsheet do
    case API.get_spreadsheet(@spreadsheet_id) do
      {:ok, response} ->
        sheets = Enum.map(response["sheets"], fn sheet -> sheet["properties"]["title"] end)
        {:ok, sheets}

      {:error, _reason} ->
        :error
    end
  end

  defp load_individual_sheet(sheet_name) do
    case API.get_individual_sheet(@spreadsheet_id, sheet_name) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        data = Jason.decode!(body)
        {:ok, data}

      {:error, _reason} ->
        :error
    end
  end
end
