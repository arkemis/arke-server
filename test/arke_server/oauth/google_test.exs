defmodule ArkeServer.OAuth.Provider.GoogleTest do
  @moduledoc """
  The certificate fetch and the clock are stubbed, so the assertions are about
  `handle_request/1`'s own validation of a signed token.
  """

  use ExUnit.Case, async: false
  use Mimic

  alias Arke.Utils.DatetimeHandler
  alias ArkeServer.OAuth.Provider.Google

  @kid "test-kid"
  @app_id "arke-test-client-id"
  @now ~U[2026-08-04 12:00:00Z]

  setup :verify_on_exit!

  setup do
    System.put_env("GOOGLE_CLIENT_ID", @app_id)
    on_exit(fn -> System.delete_env("GOOGLE_CLIENT_ID") end)

    stub(DatetimeHandler, :now, fn :datetime -> @now end)
    stub(DatetimeHandler, :from_unix, fn s -> DateTime.from_unix!(s) end)

    key = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))
    %{key: key}
  end

  defp sign(key, claims) do
    key
    |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => @kid}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp serve_certs(key, kid \\ @kid) do
    {_, map} = JOSE.JWK.to_map(key)
    keys = [Map.put(map, "kid", kid)]

    stub(Req, :get, fn _url, _opts -> {:ok, %{status: 200, body: %{"keys" => keys}}} end)
  end

  defp claims(overrides) do
    Map.merge(
      %{
        "iss" => "https://accounts.google.com",
        "aud" => @app_id,
        "exp" => DateTime.to_unix(~U[2026-08-04 13:00:00Z]),
        "sub" => "google-sub-1",
        "email" => "someone@example.com",
        "given_name" => "Some",
        "family_name" => "One"
      },
      overrides
    )
  end

  defp request(key, claim_overrides) do
    serve_certs(key)
    token = sign(key, claims(claim_overrides))

    %Plug.Conn{body_params: %{"account" => %{"id_token" => token}}}
    |> Google.handle_request()
  end

  describe "handle_request/1" do
    test "accepts a token that is signed, issued and audienced correctly", %{key: key} do
      conn = request(key, %{})

      refute Map.has_key?(conn.assigns, :arke_server_oauth_failure)
      assert conn.private[:arke_server_oauth]["sub"] == "google-sub-1"
    end

    test "rejects a token whose expiry has passed", %{key: key} do
      conn = request(key, %{"exp" => DateTime.to_unix(~U[2026-08-04 11:00:00Z])})

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end

    # `:day` sorts before `:year` in a %DateTime{}, so comparing the structs with `>`
    # reports this 2020 expiry as later than the 2026 clock and lets it through.
    test "rejects an expired token that term order would rank as still valid", %{key: key} do
      expiry = ~U[2020-01-28 00:00:00Z]

      assert DateTime.compare(expiry, @now) == :lt

      conn = request(key, %{"exp" => DateTime.to_unix(expiry)})

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end

    test "rejects an unexpected issuer", %{key: key} do
      conn = request(key, %{"iss" => "https://evil.example.com"})

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end

    test "rejects an audience that is not this client", %{key: key} do
      conn = request(key, %{"aud" => "someone-elses-client-id"})

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end

    test "rejects a token signed by a key the certificate endpoint does not serve", %{key: key} do
      serve_certs(JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32)))
      token = sign(key, claims(%{}))

      conn =
        %Plug.Conn{body_params: %{"account" => %{"id_token" => token}}}
        |> Google.handle_request()

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end

    test "rejects a request carrying no token" do
      conn = Google.handle_request(%Plug.Conn{body_params: %{}})

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end
  end

  describe "info/1 and uid/1" do
    test "read the verified claims off the conn", %{key: key} do
      conn = request(key, %{})

      assert Google.uid(conn) == "google-sub-1"

      assert %{email: "someone@example.com", first_name: "Some", last_name: "One"} =
               Google.info(conn)
    end
  end
end
