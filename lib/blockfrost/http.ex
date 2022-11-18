defmodule Blockfrost.HTTP do
  @moduledoc """
  HTTP requests to Blockfrost APIs.
  
  This module is not meant to be use directly. Use the higher level modules to do calls
  to the Blockfrost API.
  """

  @retryable_statuses [403, 429, 500]

  @type error_response ::
          {:error,
           :bad_request
           | :unauthenticated
           | :ip_banned
           | :usage_limit_reached
           | :internal_server_error
           | HTTPoison.Error.t()}

  @doc """
  Builds a request and sends it.
  
  Supports pagination.
  
  If pagination.page is `:all`, will fetch all pages concurrently, with retries
  according to retry options.  If some page fails to be fetched, the first error
  found will be returned.
  
  If you're fetching all pages, maximum concurrency can be configured by using
  the :max_concurrency option. Default is `10`.
  
  Keeps data in the order requested.
  """
  @spec build_and_send(atom(), atom(), String.t(), Keyword.t()) :: {:ok, term} | {:error, term}
  def build_and_send(
        name,
        method,
        path,
        opts \\ []
      ) do
    req = build(name, method, path, opts[:body], opts)
    request(req, opts)
  end

  defp should_fetch_more?(responses) do
    expected_count = Enum.count(responses) * 100

    result_count =
      responses
      |> Enum.map(&elem(&1, 1))
      |> Enum.map(fn
        {:ok, response} ->
          Jason.decode!(response.body)

        _e ->
          []
      end)
      |> List.flatten()
      |> Enum.count()

    expected_count == result_count
  end

  @doc """
  Builds a request to a Blockfrost API
  
  This function only builds the request. You can execute it with `request/3`.
  """
  @spec build(atom, HTTPoison.Request.method(), binary, map, binary) :: HTTPoison.Request.t()
  def build(name, method, path, query_params, opts \\ [body: ""]) do
    config = Blockfrost.config(name)
    path = resolve_path(config, path, query_params)
    headers = resolve_headers(config, opts)

    body =
      if is_nil(opts[:body]) do
        ""
      else
        opts[:body]
      end

    %HTTPoison.Request{method: method, url: path, body: body, headers: headers}
  end

  defp resolve_path(%Blockfrost.Config{network_uri: base_uri}, path, query_params) do
    query =
      URI.encode_query(
        if is_nil(query_params) do
          %{}
        else
          query_params
        end
      )

    %{base_uri | path: base_uri.path <> path, query: query}
  end

  defp resolve_headers(%Blockfrost.Config{api_key: api_key}, opts) do
    {:ok, version} = :application.get_key(:blockfrost, :vsn)

    content_type = opts[:content_type] || "application/json"

    content_length =
      if length = opts[:content_length],
        do: [{"Content-Length", inspect(length)}],
        else: []

    [
      {"project_id", api_key},
      {"User-Agent", "blockfrost-elixir/#{version}"},
      {"Content-Type", content_type}
    ] ++ content_length
  end

  @doc """
  Does a request to a Blockfrost API.
  
  Receives the following options:
  - `:retry_enabled?`: whether it should retry failing requests
  - `:retry_max_attempts`: max retry attempts
  - `:retry_interval`: interval between attempts
  
  All these options fall back to the config. If they're not defined there,
  they fall back to default values. See `Blockfrost.Config` for more info.
  
  For additional options, see `HTTPoison.request/3`
  
  Build requests with `build/4`.
  """
  def request(request, opts \\ []) do
    HTTPoison.request(request)
    |> handle_response(opts)
  end

  defp handle_response({:ok, response}, opts) do
    if opts[:skip_error_handling?] do
      {:ok, response}
    else
      case response do
        %{status_code: status} when status in 199..399 ->
          {:ok, response}

        %{status_code: 400} ->
          {:error, :bad_request}

        %{status_code: 403} ->
          {:error, :unauthenticated}

        %{status_code: 404} ->
          {:error, :not_found}

        %{status_code: 418} ->
          {:error, :ip_banned}

        %{status_code: 429} ->
          {:error, :usage_limit_reached}

        %{status_code: 500} ->
          {:error, :internal_server_error}
      end
    end
  end

  defp handle_response({:error, %{reason: reason}}, _opts), do: {:error, reason}
end
