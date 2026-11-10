defmodule SmsGoraTest do
  use ExUnit.Case, async: true

  @ok ~s({"success":true,"data":{"message_ids":[1873]}})

  # Req runs the plug in the test process, so each request is sent back to us as a message.
  defp client(status \\ 200, reply \\ @ok, headers \\ []) do
    test_pid = self()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(test_pid, %{
        method: conn.method,
        path: conn.request_path,
        query: conn.query_string,
        key: Plug.Conn.get_req_header(conn, "x-api-key") |> List.first(),
        body: if(body == "", do: nil, else: Jason.decode!(body))
      })

      conn =
        Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_resp_header(c, k, v) end)

      conn
      |> Plug.Conn.put_resp_content_type(
        if(String.starts_with?(reply, "{"), do: "application/json", else: "text/html")
      )
      |> Plug.Conn.send_resp(status, reply)
    end

    SmsGora.new("sgk_test", base_url: "https://example.test/api/", req_options: [plug: plug])
  end

  test "send_sms" do
    assert {:ok, %{"message_ids" => [1873]}} =
             SmsGora.send_sms(client(), "+15551234567", "Hi")

    assert_received %{method: "POST", path: "/api/send-sms", key: "sgk_test", body: body}
    assert body == %{"recipients" => ["+15551234567"], "message" => "Hi"}
  end

  test "device, SIM and schedule" do
    {:ok, _} =
      SmsGora.send_sms(client(), ["+1", "+2"], "x",
        device_id: 42,
        sim_slot: 1,
        schedule_at: ~U[2026-12-01 08:00:00.123Z]
      )

    assert_received %{path: "/api/devices/42/send-sms", body: body}
    assert body["sim_slot"] == 1
    assert body["schedule_at"] == "2026-12-01T08:00:00Z"
    assert body["recipients"] == ["+1", "+2"]
  end

  test "bulk and other paths" do
    c = client()

    {:ok, _} =
      SmsGora.send_bulk_sms(
        c,
        42,
        [%{recipients: ["+1"], message: "a"}, %{recipients: ["+2"]}],
        message_template: "t"
      )

    assert_received %{path: "/api/devices/42/send-bulk-sms", body: body}
    assert body["messageTemplate"] == "t"
    assert Enum.at(body["messages"], 1) == %{"recipients" => ["+2"]}

    {:ok, _} = SmsGora.list_received_sms(c, phone: "+1555", since: "2026-11-01")
    assert_received %{path: "/api/received-sms", query: "phone=%2B1555&since=2026-11-01"}

    {:ok, _} = SmsGora.list_received_sms(c, device_id: 3)
    assert_received %{path: "/api/devices/3/get-received-sms"}

    {:ok, _} = SmsGora.cancel_message(c, 7)
    assert_received %{method: "POST", path: "/api/messages/7/cancel"}

    {:ok, _} = SmsGora.create_webhook(c, "https://my.app/hook")
    assert_received %{path: "/api/webhooks", body: %{"events" => ["sms.received"]}}

    {:ok, _} = SmsGora.delete_webhook(c, 9)
    assert_received %{method: "DELETE", path: "/api/webhooks/9"}

    assert_raise ArgumentError, fn -> SmsGora.send_sms(c, [], "x") end
  end

  test "API errors" do
    reply = ~s({"success":false,"message":"Too many requests","errors":{"recipients":["bad"]}})

    assert {:error, %SmsGora.Error{} = err} =
             SmsGora.get_account(client(429, reply, [{"retry-after", "12"}]))

    assert err.status == 429
    assert err.message == "Too many requests"
    assert err.retry_after == 12.0
    assert err.errors == %{"recipients" => ["bad"]}

    assert {:error, err} = SmsGora.list_devices(client(502, "<html>bad gateway</html>"))
    assert err.message == "HTTP 502"
    assert err.body == "<html>bad gateway</html>"

    assert_raise ArgumentError, fn -> SmsGora.new("") end
  end

  test "verify_webhook" do
    raw = ~s({"event":"sms.received","data":{"from":"+15551234567"}})
    sig = "sha256=e125c07dfbecb498e8979383d7b9f0815efb128755409794b486d4bbb7199583"
    assert SmsGora.verify_webhook(raw, sig, "whsec_test")
    refute SmsGora.verify_webhook(raw, sig, "other")
    refute SmsGora.verify_webhook("{}", sig, "whsec_test")
    refute SmsGora.verify_webhook(raw, nil, "whsec_test")
  end
end
