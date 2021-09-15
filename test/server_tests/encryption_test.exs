defmodule ServerEncryptionTest do
  use ExUnit.Case

  alias OpcUA.Server

  setup do
    {:ok, pid} = OpcUA.Server.start_link
    %{pid: pid}
  end

  test "Set default configuration with all policies", %{pid: pid} do
    desired_config = [
      port: 4014,
      certificate: File.read!("./test/demo_certs/server_cert.der"),
      private_key: File.read!("./test/demo_certs/server_key.der")
    ]

    response = Server.set_default_config_with_certs(pid, desired_config)
    assert response == :ok
  end

  test "Set basics (before adding security policies)", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok
  end

  test "Set network layer (before adding security policies)", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4015)
    assert response == :ok
  end

  test "Add none security policy", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4016)
    assert response == :ok

    certs_info = [
      certificate: File.read!("./test/demo_certs/server_cert.der")
    ]

    response = Server.add_none_policy(pid, certs_info)
    assert response == :ok
  end

  test "Add basic128rsa15 security policy", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4017)
    assert response == :ok

    certs_info = [
      certificate: File.read!("./test/demo_certs/server_cert.der"),
      private_key: File.read!("./test/demo_certs/server_key.der")
    ]

    response = Server.add_basic128rsa15_policy(pid, certs_info)
    assert response == :ok
  end

  test "Add basic256 security policy", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4018)
    assert response == :ok

    certs_info = [
      certificate: File.read!("./test/demo_certs/server_cert.der"),
      private_key: File.read!("./test/demo_certs/server_key.der")
    ]

    response = Server.add_basic256_policy(pid, certs_info)
    assert response == :ok
  end

  test "Add basic256sha256 security policy", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4019)
    assert response == :ok

    certs_info = [
      certificate: File.read!("./test/demo_certs/server_cert.der"),
      private_key: File.read!("./test/demo_certs/server_key.der")
    ]

    response = Server.add_basic256sha256_policy(pid, certs_info)
    assert response == :ok
  end

  test "Add all security policies (no endpoint)", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4020)
    assert response == :ok

    certs_info = [
      certificate: File.read!("./test/demo_certs/server_cert.der"),
      private_key: File.read!("./test/demo_certs/server_key.der")
    ]

    response = Server.add_all_policies(pid, certs_info)
    assert response == :ok
  end

  test "Add none, basic256sha256 with endpoints", %{pid: pid} do
    response = Server.set_basics(pid)
    assert response == :ok

    response = Server.set_network_tcp_layer(pid, 4021)
    assert response == :ok

    certs_info = [
      certificate: File.read!("./test/demo_certs/server_cert.der"),
      private_key: File.read!("./test/demo_certs/server_key.der")
    ]

    # None policy must be added.
    response = Server.add_none_policy(pid, certs_info)
    assert response == :ok
    response = Server.add_basic256sha256_policy(pid, certs_info)
    assert response == :ok
    response = Server.add_all_endpoints(pid)
    assert response == :ok

    assert :ok == Server.start(pid)
  end
end
