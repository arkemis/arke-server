defmodule ArkeServer.HttpClientTest do
  @moduledoc """
  Covers the outbound HTTP calls: the request that goes out and the decoded
  response that comes back.

  Not async: routing Req through `Req.Test` is a global default.
  """
  use ExUnit.Case, async: false

  alias ArkeServer.OAuth.Provider.Facebook
  alias ArkeServer.Utils.OneSignal

  @client_id "fb-client-id"
  @client_secret "fb-secret"

  setup do
    Req.default_options(plug: {Req.Test, __MODULE__})
    on_exit(fn -> Req.default_options([]) end)
    :ok
  end

  defp put_env(vars) do
    for {name, value} <- vars do
      previous = System.get_env(name)
      System.put_env(name, value)
      on_exit(fn -> if previous, do: System.put_env(name, previous), else: System.delete_env(name) end)
    end
  end

  defp conn_with_token(token) do
    %Plug.Conn{query_params: %{"token" => token}, private: %{}, assigns: %{}}
  end

  describe "Facebook provider" do
    setup do
      put_env(%{"FACEBOOK_CLIENT_ID" => @client_id, "FACEBOOK_CLIENT_SECRET" => @client_secret})
      :ok
    end

    # Both endpoints in one stub, so the requests to each can be asserted.
    defp stub_facebook(debug_token_data) do
      pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        send(pid, {:request, conn.request_path, conn.query_params})

        case conn.request_path do
          "/v14.0/debug_token" ->
            Req.Test.json(conn, %{"data" => debug_token_data})

          "/v14.0/me" ->
            Req.Test.json(conn, %{
              "id" => "fb-1",
              "first_name" => "Ada",
              "last_name" => "Lovelace",
              "email" => "ada@example.com"
            })
        end
      end)
    end

    test "a valid token puts the decoded user data on the conn" do
      stub_facebook(%{"app_id" => @client_id, "is_valid" => true})

      conn = Facebook.handle_request(conn_with_token("user-token"))

      assert conn.private[:arke_server_oauth]["email"] == "ada@example.com"
      assert conn.private[:arke_server_oauth]["first_name"] == "Ada"
      refute Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end

    test "the token is debugged with the app credentials and the user fields are requested" do
      stub_facebook(%{"app_id" => @client_id, "is_valid" => true})

      Facebook.handle_request(conn_with_token("user-token"))

      assert_received {:request, "/v14.0/debug_token", debug_params}
      assert debug_params["input_token"] == "user-token"
      assert debug_params["access_token"] == "#{@client_id}|#{@client_secret}"

      assert_received {:request, "/v14.0/me", user_params}
      assert user_params["access_token"] == "user-token"
      assert user_params["fields"] == "id,first_name,last_name,email"
    end

    test "(error) a token issued to another app is rejected" do
      stub_facebook(%{"app_id" => "someone-else", "is_valid" => true})

      conn = Facebook.handle_request(conn_with_token("user-token"))

      assert {:error, _} = conn.assigns[:arke_server_oauth_failure]
      refute conn.private[:arke_server_oauth]
    end

    test "(error) an invalid token is rejected" do
      stub_facebook(%{"app_id" => @client_id, "is_valid" => false})

      conn = Facebook.handle_request(conn_with_token("user-token"))

      assert {:error, _} = conn.assigns[:arke_server_oauth_failure]
    end

    test "(error) a failed request is rejected" do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      conn = Facebook.handle_request(conn_with_token("user-token"))

      assert {:error, _} = conn.assigns[:arke_server_oauth_failure]
    end
  end

  describe "OneSignal" do
    setup do
      put_env(%{"ONESIGNAL_APP_ID" => "app-1", "ONESIGNAL_API_KEY" => "api-key"})
      :ok
    end

    test "posts the notification as json and returns the decoded response" do
      pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(pid, {:request, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), body})
        Req.Test.json(conn, %{"id" => "notification-1"})
      end)

      assert OneSignal.create_notification(%{id: "member-1"}, %{"en" => "hello"}) ==
               %{"id" => "notification-1"}

      assert_received {:request, "/api/v1/notifications", ["Basic api-key"], body}

      assert Jason.decode!(body) == %{
               "app_id" => "app-1",
               "target_channel" => "push",
               "include_aliases" => %{"external_id" => ["member-1"]},
               "contents" => %{"en" => "hello"}
             }
    end

    test "(error) returns the reason when the request fails" do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, %Req.TransportError{reason: :timeout}} =
               OneSignal.create_notification(%{id: "member-1"}, %{"en" => "hello"})
    end
  end
end
