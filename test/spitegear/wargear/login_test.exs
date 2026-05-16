defmodule Spitegear.Wargear.LoginTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Spitegear.Wargear.Login

  describe "extract_cookie/1" do
    test "extracts and joins cookie values from Set-Cookie headers" do
      headers = [
        {"Set-Cookie", "CAKEPHP=abc123; path=/; HttpOnly"},
        {"Set-Cookie", "session=xyz789; path=/; Secure"}
      ]

      assert Login.extract_cookie(headers) == "CAKEPHP=abc123; session=xyz789"
    end

    test "returns empty string when no Set-Cookie headers present" do
      headers = [{"Content-Type", "text/html"}, {"Location", "/dashboard"}]
      assert Login.extract_cookie(headers) == ""
    end

    test "is case-insensitive on the header name" do
      headers = [{"set-cookie", "CAKEPHP=abc123; path=/"}]
      assert Login.extract_cookie(headers) == "CAKEPHP=abc123"
    end

    test "strips attributes beyond the first semicolon" do
      headers = [{"Set-Cookie", "CAKEPHP=tok; path=/; HttpOnly; SameSite=Lax"}]
      assert Login.extract_cookie(headers) == "CAKEPHP=tok"
    end
  end
end
