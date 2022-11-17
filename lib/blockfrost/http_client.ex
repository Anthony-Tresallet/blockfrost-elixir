defmodule Blockfrost.HTTPClient do
  @moduledoc false

  @callback request(HTTPoison.Request.t(), atom, Keyword.t()) :: HTTPoison.Response.t()
end
