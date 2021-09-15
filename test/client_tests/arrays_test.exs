defmodule ClientArraysTest do
  use ExUnit.Case, async: false

  alias OpcUA.{NodeId, Server, QualifiedName, Client}

  setup do
    {:ok, pid} = OpcUA.Server.start_link()
    Server.set_default_config(pid)
    :ok = Server.set_port(pid, 4000)
    {:ok, ns_index} = OpcUA.Server.add_namespace(pid, "Room")

    # Object Node
    requested_new_node_id =
      NodeId.new(ns_index: ns_index, identifier_type: "string", identifier: "R1_TS1_VendorName")

    parent_node_id = NodeId.new(ns_index: 0, identifier_type: "integer", identifier: 85)
    reference_type_node_id = NodeId.new(ns_index: 0, identifier_type: "integer", identifier: 35)
    browse_name = QualifiedName.new(ns_index: ns_index, name: "Temperature sensor")
    type_definition = NodeId.new(ns_index: 0, identifier_type: "integer", identifier: 58)

    :ok = Server.add_object_node(pid,
      requested_new_node_id: requested_new_node_id,
      parent_node_id: parent_node_id,
      reference_type_node_id: reference_type_node_id,
      browse_name: browse_name,
      type_definition: type_definition
    )

    # Variable Node
    requested_new_node_id =
      NodeId.new(ns_index: ns_index, identifier_type: "string", identifier: "R1_TS1_Temperature")

    parent_node_id =
      NodeId.new(ns_index: ns_index, identifier_type: "string", identifier: "R1_TS1_VendorName")

    reference_type_node_id = NodeId.new(ns_index: 0, identifier_type: "integer", identifier: 47)
    browse_name = QualifiedName.new(ns_index: ns_index, name: "Temperature")
    type_definition = NodeId.new(ns_index: 0, identifier_type: "integer", identifier: 63)

    :ok = Server.add_variable_node(pid,
      requested_new_node_id: requested_new_node_id,
      parent_node_id: parent_node_id,
      reference_type_node_id: reference_type_node_id,
      browse_name: browse_name,
      type_definition: type_definition
    )

    :ok = Server.write_node_access_level(pid, requested_new_node_id, 3)
    :ok = Server.write_node_write_mask(pid, requested_new_node_id, 3)
    :ok = Server.write_node_value_rank(pid, requested_new_node_id, 1)
    :ok = Server.write_node_array_dimensions(pid, requested_new_node_id, [4])
    :ok = Server.write_node_blank_array(pid, requested_new_node_id, 11, [4])

    :ok = Server.start(pid)

    {:ok, c_pid} = Client.start_link()
    :ok = Client.set_config(c_pid)
    :ok = Client.connect_by_url(c_pid, url: "opc.tcp://localhost:4000/")

    %{c_pid: c_pid, s_pid: pid, ns_index: ns_index}
  end

  test "write/read array dimension node", state do
    node_id = NodeId.new(ns_index: state.ns_index, identifier_type: "string", identifier: "R1_TS1_Temperature")

    resp = Client.write_node_array_dimensions(state.c_pid, node_id, [4])
    assert resp == :ok

    resp = Client.read_node_array_dimensions(state.c_pid, node_id)
    assert resp == {:ok, [4]}

    resp = Client.write_node_array_dimensions(state.c_pid, node_id, [4])
    assert resp == :ok

    resp = Client.read_node_array_dimensions(state.c_pid, node_id)
    assert resp == {:ok, [4]}
  end

  test "write/read array node by index (string)", state do
    node_id = NodeId.new(ns_index: state.ns_index, identifier_type: "string", identifier: "R1_TS1_Temperature")

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 0)
    assert resp == {:ok, ""}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 1)
    assert resp == {:ok, ""}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 2)
    assert resp == {:ok, ""}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 3)
    assert resp == {:ok, ""}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.write_node_value(state.c_pid, node_id, 11, "alde103_1", 0)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 11, "alde103_2", 1)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 11, "alde103_3", 2)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 11, "alde103_4", 3)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 11, "alde103_error", 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 0)
    assert resp == {:ok, "alde103_1"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 1)
    assert resp == {:ok, "alde103_2"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 2)
    assert resp == {:ok, "alde103_3"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 3)
    assert resp == {:ok, "alde103_4"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.read_node_value(state.c_pid, node_id)
    assert resp == {:ok, ["alde103_1", "alde103_2", "alde103_3", "alde103_4"]}
  end

  test "write/read array node by index (double)", state do
    node_id = NodeId.new(ns_index: state.ns_index, identifier_type: "string", identifier: "R1_TS1_Temperature")
    :ok = Server.write_node_blank_array(state.s_pid, node_id, 10, [4])

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 0)
    assert resp == {:ok, 0.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 1)
    assert resp == {:ok, 0.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 2)
    assert resp == {:ok, 0.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 3)
    assert resp == {:ok, 0.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.write_node_value(state.c_pid, node_id, 10, 103.0, 0)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 10, 103103.0, 1)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 10, 103103103.0, 2)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 10, 103103.103, 3)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 10, 103103.0, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 0)
    assert resp == {:ok, 103.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 1)
    assert resp == {:ok, 103103.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 2)
    assert resp == {:ok, 103103103.0}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 3)
    assert resp == {:ok, 103103.103}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.read_node_value(state.c_pid, node_id)
    assert resp == {:ok, [103.0, 103103.0, 103103103.0, 103103.103]}
  end

  test "write/read array node by index (node_id)", state do
    node_id = NodeId.new(ns_index: state.ns_index, identifier_type: "string", identifier: "R1_TS1_Temperature")
    :ok = Server.write_node_blank_array(state.s_pid, node_id, 16, [4])

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 0)
    assert resp == {:ok, %OpcUA.NodeId{identifier: 0, identifier_type: 0, ns_index: 0}}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 1)
    assert resp == {:ok, %OpcUA.NodeId{identifier: 0, identifier_type: 0, ns_index: 0}}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 2)
    assert resp == {:ok, %OpcUA.NodeId{identifier: 0, identifier_type: 0, ns_index: 0}}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 3)
    assert resp == {:ok, %OpcUA.NodeId{identifier: 0, identifier_type: 0, ns_index: 0}}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.write_node_value(state.c_pid, node_id, 16, node_id, 0)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 16, node_id, 1)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 16, node_id, 2)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 16, node_id, 3)
    assert resp == :ok

    resp = Client.write_node_value(state.c_pid, node_id, 16, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 0)
    assert resp == {:ok, node_id}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 1)
    assert resp == {:ok, node_id}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 2)
    assert resp == {:ok, node_id}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 3)
    assert resp == {:ok, node_id}

    resp = Client.read_node_value_by_index(state.c_pid, node_id, 4)
    assert resp == {:error, "BadTypeMismatch"}

    resp = Client.read_node_value(state.c_pid, node_id)
    assert resp == {:ok, [node_id, node_id, node_id, node_id]}
  end
end
