defmodule GoogleAuth do
  use GenServer

  @token_url "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/spreadsheets"

  #random comment

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  def get_token do
    GenServer.call(__MODULE__, :get_token)
  end

  @impl true
  def handle_call(:get_token, _from, state) do
    t = :os.system_time(:second)

    case state do
      %{token: token, expires_at: expires_at} when expires_at > t ->
        {:reply, token, state}

      _ ->
        {:ok, token, expires_at} = fetch_new_token()
        new_state = %{token: token, expires_at: expires_at}
        {:reply, token, new_state}
    end
  end

  defp fetch_new_token do
    {:ok, private_key} = System.fetch_env("GSS_PRIVATE_KEY")
    {:ok, client_email} = System.fetch_env("GOOGLE_CLIENT_EMAIL")

    private_key = String.replace(private_key, "\\n", "\n")

    jwt = create_jwt(client_email, private_key)
    exchange_jwt_for_token(jwt)
  end

  defp create_jwt(client_email, private_key) do
    iat = :os.system_time(:second)
    exp = iat + 3600

    payload = %{
      "iss" => client_email,
      "scope" => @scope,
      "aud" => @token_url,
      "exp" => exp,
      "iat" => iat
    }

    jwk = JOSE.JWK.from_pem(private_key)
    jwt = JOSE.JWT.sign(jwk, %{"alg" => "RS256"}, payload)
    {_, signed_jwt} = JOSE.JWS.compact(jwt)
    signed_jwt
  end

  defp exchange_jwt_for_token(jwt) do
    body =
      %{
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => jwt
      }
      |> Jason.encode!()

    headers = [
      {"Content-Type", "application/json"}
    ]

    _ = Finch.start_link(name: :google_auth)

    case Finch.build(:post, @token_url, headers, body) |> Finch.request(:google_auth) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        response = Jason.decode!(body)
        token = response["access_token"]
        expires_in = response["expires_in"]
        expires_at = :os.system_time(:second) + expires_in
        {:ok, token, expires_at}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
