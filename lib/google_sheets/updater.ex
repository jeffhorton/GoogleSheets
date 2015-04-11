defmodule GoogleSheets.Updater do

  @moduledoc """
  GenServer for updating and polling a spreadsheet.
  """

  use GenServer
  require Logger
  alias GoogleSheets.Utils

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, [name: config[:id]])
  end

  # Initial update
  def init(config) do
    Logger.info "Starting updater process for spreadsheet #{config[:id]}"
    result = load_spreadsheet config, Keyword.fetch!(config, :loader_init)
    update_ets_entry config, result
    schedule_next_update config, Keyword.fetch!(config, :poll_delay_seconds)
    {:ok, config}
  end

  # Polling update
  def handle_info(:update, config) do
    result = load_spreadsheet config, Keyword.fetch!(config, :loader_poll)
    update_ets_entry config, result
    schedule_next_update config, Keyword.fetch!(config, :poll_delay_seconds)
    {:noreply, config}
  end

  # Load spreadsheet data with a configured loader
  defp load_spreadsheet(config, loader_config) do
    sheets = Keyword.fetch! config, :sheets
    module = Keyword.fetch! loader_config, :module
    module.load sheets, latest_version(config[:id]), loader_config
  end

  # Update ets table or notify that the data loaded was unchanged
  defp update_ets_entry(_config, :error), do: :error
  defp update_ets_entry(config, :unchanged), do: on_unchanged(Keyword.fetch!(config, :callback_module), Keyword.fetch!(config, :id))
  defp update_ets_entry(config, {version, spreadsheet}) do
    id = Keyword.fetch! config, :id
    key = UUID.uuid1
    callback_module = Keyword.fetch! config, :callback_module

    Logger.info "Updating spredsheet: #{inspect id} version: #{inspect version} key: #{inspect key}"

    data = on_loaded callback_module, id, spreadsheet

    :ets.insert Utils.ets_table, {{id, key}, version, data}
    :ets.insert Utils.ets_table, {{id, :latest}, version, key}

    on_saved callback_module, id, data
  end

  # If update_delay has been configured to 0, no updates will be done
  defp schedule_next_update(config, 0) do
    Logger.info "Stopping scheduled updates for #{config[:id]}"
  end
  defp schedule_next_update(_config, delay_seconds) do
    Process.send_after self, :update, delay_seconds * 1000
  end

  #
  # Callbacks if defined on configuration
  #

  defp on_loaded(nil, _id, spreadsheet), do: spreadsheet
  defp on_loaded(module, id, spreadsheet), do: module.on_loaded(id, spreadsheet)

  defp on_saved(nil, _id, data), do: data
  defp on_saved(module, id, data), do: module.on_saved(id, data)

  defp on_unchanged(nil, _id), do: nil
  defp on_unchanged(module, id), do: module.on_unchanged id

  #
  # Helpers
  #
  defp latest_version(id) when is_atom(id) do
    case :ets.lookup Utils.ets_table, {id, :latest} do
      [{_lookup_key, updated, _key}] ->
        updated
      _ ->
        nil
    end
  end

end
