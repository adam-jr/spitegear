defmodule Spitegear.Wargear.HTTP.ProxyTest do
  @moduledoc false
  use Spitegear.DataCase, async: true

  alias Spitegear.Settings
  alias Spitegear.Wargear.HTTP.Proxy

  describe "req_options/0" do
    test "returns no options when the setting is unset" do
      assert Proxy.req_options() == []
    end

    test "returns no options when the setting is blank" do
      Settings.put("wargear_proxy_url", "")

      assert Proxy.req_options() == []
    end

    test "builds a connect_options proxy tuple from a plain proxy URL" do
      Settings.put("wargear_proxy_url", "http://proxy.example.com:8888")

      assert Proxy.req_options() == [
               connect_options: [proxy: {:http, "proxy.example.com", 8888, []}]
             ]
    end

    test "adds proxy-authorization header when userinfo is present" do
      Settings.put("wargear_proxy_url", "http://user:pass@proxy.example.com:8888")

      assert Proxy.req_options() == [
               connect_options: [
                 proxy: {:http, "proxy.example.com", 8888, []},
                 proxy_headers: [
                   {"proxy-authorization", "Basic " <> Base.encode64("user:pass")}
                 ]
               ]
             ]
    end

    test "treats an https proxy scheme as :https" do
      Settings.put("wargear_proxy_url", "https://proxy.example.com:443")

      assert Proxy.req_options() == [
               connect_options: [proxy: {:https, "proxy.example.com", 443, []}]
             ]
    end
  end
end
