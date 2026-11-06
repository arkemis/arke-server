defmodule ArkeServer.OAuth.Provider.MicrosoftTest do
  @moduledoc """
  The key discovery endpoint, the Graph call and the clock are stubbed, so the
  assertions are about `handle_request/1`'s own validation of a signed token.
  """

  use ExUnit.Case, async: false
  use Mimic

  alias Arke.Utils.DatetimeHandler
  alias ArkeServer.OAuth.Provider.Microsoft

  @tenant "arke-test-tenant"
  @now ~U[2026-08-04 12:00:00Z]

  setup :verify_on_exit!

  setup do
    System.put_env("AZURE_TENANT_ID", @tenant)
    on_exit(fn -> System.delete_env("AZURE_TENANT_ID") end)

    stub(DatetimeHandler, :now, fn :datetime -> @now end)
    stub(DatetimeHandler, :from_unix, fn s -> DateTime.from_unix!(s) end)

    %{key: JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))}
  end

  defp sign(key, claims) do
    key
    |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp claims(overrides) do
    Map.merge(
      %{
        "iss" => "https://login.microsoftonline.com/#{@tenant}/v2.0",
        "tid" => @tenant,
        "exp" => DateTime.to_unix(~U[2026-08-04 13:00:00Z]),
        "sub" => "ms-sub-1"
      },
      overrides
    )
  end

  defp request(key, claim_overrides, signing_key \\ nil) do
    {_, key_map} = JOSE.JWK.to_map(key)

    ok = fn body -> {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}} end

    stub(HTTPoison, :get, fn _keys_url -> ok.(%{"keys" => [key_map]}) end)
    stub(HTTPoison, :get, fn _graph_url, _headers -> ok.(%{"mail" => "someone@example.com"}) end)

    token = sign(signing_key || key, claims(claim_overrides))

    %Plug.Conn{body_params: %{"id_token" => token, "access_token" => "graph-token"}}
    |> Microsoft.handle_request()
  end

  describe "handle_request/1" do
    test "accepts a token with a valid signature, issuer, tenant and expiry", %{key: key} do
      conn = request(key, %{})

      refute Map.has_key?(conn.assigns, :arke_server_oauth_failure)
      assert conn.private[:arke_server_oauth]["mail"] == "someone@example.com"
    end

    test "rejects a token whose expiry has passed", %{key: key} do
      conn = request(key, %{"exp" => DateTime.to_unix(~U[2026-08-04 11:00:00Z])})

      assert conn.assigns[:arke_server_oauth_failure] == "Token expired"
    end

    test "rejects an unexpected issuer", %{key: key} do
      conn = request(key, %{"iss" => "https://login.microsoftonline.com/someone-else/v2.0"})

      assert conn.assigns[:arke_server_oauth_failure] == "Invalid issuer"
    end

    test "rejects a token for another tenant", %{key: key} do
      conn = request(key, %{"tid" => "someone-elses-tenant"})

      assert conn.assigns[:arke_server_oauth_failure] == "Invalid tenant"
    end

    test "rejects a token signed with a key the tenant does not publish", %{key: key} do
      forged_with = JOSE.JWK.from_oct(:crypto.strong_rand_bytes(32))
      conn = request(key, %{}, forged_with)

      assert conn.assigns[:arke_server_oauth_failure] == "Invalid signature"
      refute conn.private[:arke_server_oauth]
    end

    test "rejects a request carrying no token" do
      conn = Microsoft.handle_request(%Plug.Conn{body_params: %{}})

      assert Map.has_key?(conn.assigns, :arke_server_oauth_failure)
    end
  end
end
