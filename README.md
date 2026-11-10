# SmsGora

[![Hex.pm](https://img.shields.io/hexpm/v/smsgora.svg)](https://hex.pm/packages/smsgora)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/smsgora)
[![tests](https://github.com/TekservixHQ/smsgora-elixir/actions/workflows/tests.yml/badge.svg)](https://github.com/TekservixHQ/smsgora-elixir/actions/workflows/tests.yml)

Elixir client for the [SMS Gora SMS Gateway](https://tekservix.com/smsgora/) API.

SMS Gora turns Android phones with ordinary SIM cards into an SMS gateway. Your server calls the API, a linked phone sends the text, and replies and delivery reports come back to you. There's no sender ID registration and no per-message fee from us: your mobile operator bills the texts like any SMS.

- Built on [Req](https://hex.pm/packages/req); works in Phoenix, Oban jobs, LiveView and scripts
- Plain `{:ok, data}` / `{:error, %SmsGora.Error{}}` results
- Webhook signature check built in

## Installation

Add `smsgora` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:smsgora, "~> 1.0"}
  ]
end
```

## Quick start

Create an API key in the SMS Gora dashboard (SMS Gora -> API keys) and keep it on your server.

```elixir
client = SmsGora.new(System.fetch_env!("SMSGORA_KEY"))

{:ok, %{"message_ids" => [id]}} =
  SmsGora.send_sms(client, "+15551234567", "Your verification code is 482913")
```

## Sending

```elixir
# Several recipients (up to 1,000 per call)
SmsGora.send_sms(client, ["+15551234567", "+447700900123"], "Your order has shipped")

# From a chosen phone and SIM, scheduled for later
SmsGora.send_sms(client, "+15551234567", "Reminder: your appointment is tomorrow at 10:00",
  device_id: 42,
  sim_slot: 1, # 0 = SIM 1, 1 = SIM 2
  schedule_at: ~U[2026-12-01 08:00:00Z]
)

# Different texts for different people in one call (up to 5,000 recipients)
SmsGora.send_bulk_sms(client, 42, [
  %{recipients: ["+15551234567"], message: "Hi Aline, parcel #1042 is ready."},
  %{recipients: ["+15557654321"]}
], message_template: "Hello, your parcel is ready for pickup.")
```

## Delivery status and incoming SMS

```elixir
{:ok, msg} = SmsGora.get_message(client, 1873)
msg["status"] # queued -> dispatched -> sent -> delivered (or failed)

SmsGora.cancel_message(client, 1874) # works while queued or scheduled

{:ok, inbox} = SmsGora.list_received_sms(client, since: "2026-11-01", limit: 50)
{:ok, phones} = SmsGora.list_devices(client)
{:ok, account} = SmsGora.get_account(client)
```

Anything else in the [API reference](https://tekservix.com/smsgora/docs/) is one call away:

```elixir
SmsGora.request(client, :get, "/batches/311")
```

## Webhooks

Add your HTTPS URL in SMS Gora -> Webhooks (or with `create_webhook/3`) and keep the secret. Each request carries `X-SmsGora-Signature: sha256=...`, an HMAC-SHA256 of the raw body. In Phoenix, keep the raw body with a `body_reader` in `Plug.Parsers`, then:

```elixir
def sms_webhook(conn, params) do
  signature = conn |> get_req_header("x-smsgora-signature") |> List.first()

  if SmsGora.verify_webhook(conn.assigns.raw_body, signature, System.fetch_env!("SMSGORA_WEBHOOK_SECRET")) do
    if params["event"] == "sms.received" do
      # params["data"]["from"], params["data"]["message"]: enqueue an Oban job
    end

    send_resp(conn, 200, "ok") # answer within 10 seconds
  else
    send_resp(conn, 401, "bad signature")
  end
end
```

## Errors

Failed calls return `{:error, %SmsGora.Error{}}` with `status`, `message`, field `errors` and, on 429, `retry_after` in seconds.

```elixir
case SmsGora.send_sms(client, "+15551234567", "Hi") do
  {:ok, result} -> result
  {:error, %SmsGora.Error{status: 429, retry_after: wait}} -> Process.sleep(trunc((wait || 5) * 1000))
  {:error, error} -> raise error
end
```

Never put the key in a browser or mobile app: anyone could read it. Call the API from your server.

## Migrating from TextBee

SMS Gora accepts TextBee-style requests, so most integrations switch by changing the base URL and key. See the [compatibility notes](https://tekservix.com/smsgora/docs/).

## More from Tekservix

- [WAservix WhatsApp API Gateway](https://tekservix.com/waservix/): send WhatsApp messages from your own number ([`{:waservix, "~> 1.0"}`](https://hex.pm/packages/waservix))
- [AI Sales Agent](https://tekservix.com/ai-sales-agent): answers customers on WhatsApp and SMS using your website's content
- [Website to App](https://tekservix.com/mobile-apps): turn your website into Android and iOS apps
- SMS Gora is also on npm, PyPI, Packagist, Go, Maven (JitPack), NuGet, RubyGems, Swift, crates.io, pub.dev and JSR: see [github.com/TekservixHQ](https://github.com/TekservixHQ)

## License

MIT
