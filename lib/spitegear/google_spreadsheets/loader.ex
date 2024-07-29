defmodule Spitegear.GoogleSpreadsheets.Loader do
  use GenServer

  require Logger

  alias Spitegear.GoogleSpreadsheets.API
  alias Spitegear.GoogleSpreadsheets.Sheets

  @spreadsheet_id "1qhTcmKRpnmknMV3opGv1jdpQ1d6hFCU862lIRy1jL-Q"

  # Public API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def fetch_sheet_data(sheet_name) do
    GenServer.call(__MODULE__, {:fetch_sheet_data, sheet_name})
  end

  def refresh do
    send(__MODULE__, :load_google_sheet)
  end

  def start_games do
    send(__MODULE__, :start_games)
  end

  # Callbacks
  @impl true
  def init(_opts) do
    schedule_retry(0)
    {:ok, %{retry_count: 0, sheets: [], current_sheet: nil, data: %{}}}
  end

  @impl true
  def handle_call({:fetch_sheet_data, sheet_name}, _from, state) do
    case get_in(state, [:data, sheet_name]) do
      nil ->
        {:reply, :error, state}

      data ->
        {:reply, {:ok, data}, state}
    end
  end

  @impl true
  def handle_info(:load_google_sheet, %{retry_count: retry_count} = state) do
    Logger.info("Started loading sheets")

    case load_all_sheets() do
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
    case load_sheet_data(current_sheet) do
      {:ok, data} ->
        schedule_sheet_processing()

        {:noreply,
         %{
           state
           | sheets: remaining_sheets,
             current_sheet: current_sheet,
             data: Map.put(data, current_sheet, parse_sheet(current_sheet, data))
         }}

      :error ->
        schedule_sheet_processing()
        {:noreply, %{state | sheets: remaining_sheets, current_sheet: current_sheet}}
    end
  end

  @impl true
  def handle_info(:process_next_sheet, %{sheets: []} = state) do
    Logger.info("Finished loading sheets!")
    load_games(state.data["games"])
    {:noreply, state}
  end

  @sheets [
    games: Sheets.Games
  ]
  defp parse_sheet(sheet_name, %{"values" => values}) do
    case Keyword.get(@sheets, String.to_atom(sheet_name)) do
      nil ->
        []

      module ->
        module.from_data(values) |> IO.inspect()
    end
  end

  defp load_games(rows) do
    Enum.each(rows, fn row ->
      if is_nil(row.finished) do
        DynamicSupervisor.start_child(
          GameSupervisor,
          Spitegear.Worker.GamePoller.child_spec(game_id: row.game_id)
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

  defp load_all_sheets do
    case API.get_spreadsheet(@spreadsheet_id) do
      {:ok, response} ->
        sheets = Enum.map(response["sheets"], fn sheet -> sheet["properties"]["title"] end)
        {:ok, sheets}

      {:error, _reason} ->
        :error
    end
  end

  defp load_sheet_data(sheet_name) do
    case API.get_individual_sheet(@spreadsheet_id, sheet_name) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        data = Jason.decode!(body)
        {:ok, data}

      {:error, _reason} ->
        :error
    end
  end
end
