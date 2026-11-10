defmodule SmsGora do
  @moduledoc """
  Elixir client for the [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) API.

  SMS Gora turns Android phones with ordinary SIM cards into an SMS gateway: your server
  calls the API, a linked phone sends the text, and replies and delivery reports come back.

      client = SmsGora.new(System.fetch_env!("SMSGORA_KEY"))
      {:ok, %{"message_ids" => [id]}} = SmsGora.send_sms(client, "+15551234567", "Your code is 482913")

  Every function returns `{:ok, data}` (the decoded `data` field of the answer) or
  `{:error, %SmsGora.Error{}}`. Keep the API key on your server.

  API reference: https://tekservix.com/smsgora/docs/
  """

  defmodule Error do
    @moduledoc """
    Returned when the API answers with an error, or the request fails.

    `status` is the HTTP status (0 when the request never reached the API) and
    `retry_after` is the number of seconds to wait after a 429.
    """
    defexception [:status, :message, :errors, :body, :retry_after]

    @type t :: %__MODULE__{
            status: non_neg_integer(),
            message: String.t(),
            errors: map() | nil,
            body: term(),
            retry_after: number() | nil
          }
  end

  @version Mix.Project.config()[:version]
  @default_base_url "https://tekservix.com/smsgora/api/v1"

  defstruct [:req]

  @typedoc "A client. Create one with `new/2` and reuse it."
  @type t :: %__MODULE__{req: Req.Request.t()}

  @typedoc "Result of every API call."
  @type result :: {:ok, term()} | {:error, Error.t()}

  @doc """
  Creates a client with your API key (starts with `sgk_`, from SMS Gora -> API keys).

  Options:

    * `:base_url` - change only for testing
    * `:receive_timeout` - milliseconds to wait for an answer (default 30_000)
    * `:req_options` - extra options passed to `Req.new/1` (proxy, plug for tests, ...)
  """
  @spec new(String.t(), keyword()) :: t()
  def new(api_key, opts \\ []) when is_binary(api_key) do
    if api_key == "" do
      raise ArgumentError, "SmsGora: api_key is required (create one in SMS Gora -> API keys)"
    end

    req =
      Req.new(
        [
          base_url: String.trim_trailing(Keyword.get(opts, :base_url, @default_base_url), "/"),
          headers: [
            {"x-api-key", api_key},
            {"accept", "application/json"},
            {"user-agent", "smsgora-elixir/#{@version}"}
          ],
          receive_timeout: Keyword.get(opts, :receive_timeout, 30_000),
          retry: false
        ] ++ Keyword.get(opts, :req_options, [])
      )

    %__MODULE__{req: req}
  end

  @doc """
  Calls any documented endpoint, e.g. `request(client, :get, "/devices")`.
  Returns the `data` field of the answer.
  """
  @spec request(t(), atom(), String.t(), map() | nil, keyword()) :: result()
  def request(%__MODULE__{req: req}, method, path, body \\ nil, params \\ []) do
    opts = [method: method, url: path]
    opts = if body, do: Keyword.put(opts, :json, body), else: opts
    opts = if params != [], do: Keyword.put(opts, :params, params), else: opts

    case Req.request(req, opts) do
      {:ok, %Req.Response{status: status, body: body} = resp} ->
        handle(status, body, resp)

      {:error, exception} ->
        {:error,
         %Error{status: 0, message: "SmsGora: request failed (#{Exception.message(exception)})"}}
    end
  end

  defp handle(status, body, resp) do
    map = if is_map(body), do: body, else: nil

    if status >= 400 or (map && map["success"] == false) do
      {:error,
       %Error{
         status: status,
         message: (map && is_binary(map["message"]) && map["message"]) || "HTTP #{status}",
         errors: map && map["errors"],
         body: body,
         retry_after: retry_after(resp)
       }}
    else
      {:ok, if(map && Map.has_key?(map, "data"), do: map["data"], else: body)}
    end
  end

  defp retry_after(resp) do
    case Req.Response.get_header(resp, "retry-after") do
      [value | _] ->
        case Float.parse(String.trim(value)) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Sends an SMS to one number or a list (up to 1,000). Uses your best online phone unless
  `:device_id` is given. Returns `{:ok, %{"message_ids" => [...]}}`.

  Options: `:device_id`, `:sim_slot` (0 = SIM 1, 1 = SIM 2), `:schedule_at`
  (`DateTime` or ISO 8601 string).
  """
  @spec send_sms(t(), String.t() | [String.t()], String.t(), keyword()) :: result()
  def send_sms(client, to, message, opts \\ []) do
    recipients = List.wrap(to)

    if recipients == [] do
      raise ArgumentError, "send_sms: at least one recipient is required"
    end

    body =
      %{"recipients" => recipients, "message" => message}
      |> put_opt("sim_slot", opts[:sim_slot])
      |> put_opt("schedule_at", iso8601(opts[:schedule_at]))

    path =
      case opts[:device_id] do
        nil -> "/send-sms"
        id -> "/devices/#{esc(id)}/send-sms"
      end

    request(client, :post, path, body)
  end

  @doc """
  Different texts for different people in one call (up to 5,000 recipients).

      SmsGora.send_bulk_sms(client, 42, [
        %{recipients: ["+15551234567"], message: "Hi Aline, parcel #1042 is ready."},
        %{recipients: ["+15557654321"]}
      ], message_template: "Hello, your parcel is ready for pickup.")
  """
  @spec send_bulk_sms(t(), integer() | String.t(), [map()], keyword()) :: result()
  def send_bulk_sms(client, device_id, messages, opts \\ []) do
    body = put_opt(%{"messages" => messages}, "messageTemplate", opts[:message_template])
    request(client, :post, "/devices/#{esc(device_id)}/send-bulk-sms", body)
  end

  @doc "One message. Status is queued, dispatched, sent, delivered, failed or cancelled."
  @spec get_message(t(), integer() | String.t()) :: result()
  def get_message(client, id), do: request(client, :get, "/messages/#{esc(id)}")

  @doc "Cancels a queued or scheduled message."
  @spec cancel_message(t(), integer() | String.t()) :: result()
  def cancel_message(client, id), do: request(client, :post, "/messages/#{esc(id)}/cancel")

  @doc "Sent and received messages. Filters: direction, status, device_id, phone, since, after_id, page, limit."
  @spec list_messages(t(), keyword()) :: result()
  def list_messages(client, filters \\ []),
    do: request(client, :get, "/messages", nil, clean(filters))

  @doc "Incoming SMS for all phones, or one phone with `device_id:`. Other filters as in `list_messages/2`."
  @spec list_received_sms(t(), keyword()) :: result()
  def list_received_sms(client, filters \\ []) do
    {device_id, rest} = Keyword.pop(filters, :device_id)

    path =
      if device_id, do: "/devices/#{esc(device_id)}/get-received-sms", else: "/received-sms"

    request(client, :get, path, nil, clean(rest))
  end

  @doc "One bulk batch."
  @spec get_batch(t(), integer() | String.t()) :: result()
  def get_batch(client, id), do: request(client, :get, "/batches/#{esc(id)}")

  @doc "Your linked Android phones."
  @spec list_devices(t()) :: result()
  def list_devices(client), do: request(client, :get, "/devices")

  @doc "One phone."
  @spec get_device(t(), integer() | String.t()) :: result()
  def get_device(client, id), do: request(client, :get, "/devices/#{esc(id)}")

  @doc "Account, plan and usage."
  @spec get_account(t()) :: result()
  def get_account(client), do: request(client, :get, "/account")

  @doc "Your webhooks."
  @spec list_webhooks(t()) :: result()
  def list_webhooks(client), do: request(client, :get, "/webhooks")

  @doc """
  Registers a webhook. Options: `:events` (default `["sms.received"]`), `:device_id`.
  The answer includes the secret, returned only once.
  """
  @spec create_webhook(t(), String.t(), keyword()) :: result()
  def create_webhook(client, url, opts \\ []) do
    request(client, :post, "/webhooks", %{
      "url" => url,
      "events" => Keyword.get(opts, :events, ["sms.received"]),
      "device_id" => opts[:device_id]
    })
  end

  @doc "Deletes a webhook."
  @spec delete_webhook(t(), integer() | String.t()) :: result()
  def delete_webhook(client, id), do: request(client, :delete, "/webhooks/#{esc(id)}")

  @doc """
  Checks the `X-SmsGora-Signature` header (`sha256=<hex HMAC-SHA256 of the raw body>`).
  Pass the raw request body exactly as received, before JSON parsing.

  In Phoenix, keep the raw body with a custom `body_reader` in `Plug.Parsers`, then:

      SmsGora.verify_webhook(raw_body, get_req_header(conn, "x-smsgora-signature") |> List.first(), secret)
  """
  @spec verify_webhook(binary(), String.t() | nil, String.t()) :: boolean()
  def verify_webhook(raw_body, signature, secret)
      when is_binary(raw_body) and raw_body != "" and is_binary(signature) and signature != "" and
             is_binary(secret) and secret != "" do
    expected =
      "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, raw_body), case: :lower)

    secure_compare(expected, signature)
  end

  def verify_webhook(_raw_body, _signature, _secret), do: false

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_a, _b), do: false

  defp put_opt(map, _key, nil), do: map
  defp put_opt(map, key, value), do: Map.put(map, key, value)

  defp iso8601(nil), do: nil

  defp iso8601(%DateTime{} = dt),
    do: dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp iso8601(value) when is_binary(value), do: value

  defp clean(filters), do: Enum.reject(filters, fn {_k, v} -> v in [nil, ""] end)

  defp esc(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
end
