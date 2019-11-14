defmodule Bandit.ConnAdapter do
  alias Bandit.HTTPRequest

  def run(req, {plug, plug_opts}) do
    case conn(req) do
      {:ok, conn} ->
        %Plug.Conn{adapter: {_, req}} =
          conn
          |> plug.call(plug_opts)
          |> commit_response()

        {:ok, req}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp conn(req) do
    case HTTPRequest.read_headers(req) do
      {:ok, headers, req} ->
        %{address: remote_ip} = HTTPRequest.get_peer_data(req)
        %{port: local_port} = HTTPRequest.get_local_data(req)

        # TODO read method / path / querystring etc

        {:ok,
         %Plug.Conn{
           adapter: {HTTPRequest, req},
           owner: self(),
           remote_ip: remote_ip,
           port: local_port,
           req_headers: headers
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_response(%Plug.Conn{state: :unset}), do: raise(Plug.Conn.NotSentError)
  defp commit_response(%Plug.Conn{state: :set} = conn), do: Plug.Conn.send_resp(conn)
  defp commit_response(%Plug.Conn{} = conn), do: conn
end
