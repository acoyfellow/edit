defmodule EditRuntime.WorkflowTest do
  use ExUnit.Case, async: false

  setup do
    saved = %{
      typesafe: System.get_env("TYPESAFE_API_KEY"),
      cloudflare: System.get_env("AI_GATEWAY_TOKEN"),
      account: System.get_env("CLOUDFLARE_ACCOUNT_ID")
    }

    System.delete_env("TYPESAFE_API_KEY")
    System.delete_env("AI_GATEWAY_TOKEN")
    System.delete_env("CLOUDFLARE_ACCOUNT_ID")

    on_exit(fn ->
      restore_env("TYPESAFE_API_KEY", saved.typesafe)
      restore_env("AI_GATEWAY_TOKEN", saved.cloudflare)
      restore_env("CLOUDFLARE_ACCOUNT_ID", saved.account)
    end)
  end

  test "approved fixture produces a verified receipt" do
    root = Path.join(System.tmp_dir!(), "edit-workflow-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    path = Path.join(root, "note.txt")
    File.write!(path, "draft\n")

    request = %{
      "version" => 1,
      "workspace_root" => root,
      "operations" => [
        %{
          "type" => "replace_text",
          "path" => "note.txt",
          "expected" => "draft\n",
          "replacement" => "published\n"
        }
      ],
      "verification" => %{
        "type" => "file_equals",
        "path" => "note.txt",
        "expected" => "published\n"
      },
      "capabilities" => ["workspace.read", "workspace.write"],
      "permissions" => %{"." => ["replace_text"]}
    }

    approval = %{"request_digest" => digest(request), "capabilities" => request["capabilities"]}
    receipt = EditRuntime.Workflow.run(%{"request" => request, "approval" => approval})

    assert receipt.status == "succeeded"
    assert receipt.verification.status == "passed"
    assert File.read!(path) == "published\n"
    File.rm_rf!(root)
  end

  test "path escape is denied without changing files" do
    root = Path.join(System.tmp_dir!(), "edit-workflow-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    request = %{
      "version" => 1,
      "workspace_root" => root,
      "operations" => [
        %{
          "type" => "replace_text",
          "path" => "../outside.txt",
          "expected" => "draft\n",
          "replacement" => "published\n"
        }
      ],
      "capabilities" => ["workspace.read", "workspace.write"],
      "permissions" => %{"." => ["replace_text"]}
    }

    approval = %{"request_digest" => digest(request), "capabilities" => request["capabilities"]}

    receipt = EditRuntime.Workflow.run(%{"request" => request, "approval" => approval})

    assert receipt.status == "denied"
    assert receipt.effects == []
    File.rm_rf!(root)
  end

  test "missing capability is denied before execution" do
    request = %{
      "version" => 1,
      "workspace_root" => "/tmp",
      "operations" => [],
      "capabilities" => ["workspace.write"],
      "permissions" => %{"." => ["replace_text"]}
    }

    approval = %{"request_digest" => digest(request), "capabilities" => ["workspace.read"]}

    receipt = EditRuntime.Workflow.run(%{"request" => request, "approval" => approval})

    assert receipt.status == "denied"
    assert receipt.error == "approval does not grant every requested capability"
  end

  test "write outside granted folders is denied" do
    root = Path.join(System.tmp_dir!(), "edit-workflow-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "docs"))
    File.write!(Path.join(root, "docs/readme.txt"), "draft\n")

    request = %{
      "version" => 1,
      "workspace_root" => root,
      "operations" => [
        %{
          "type" => "replace_text",
          "path" => "docs/readme.txt",
          "expected" => "draft\n",
          "replacement" => "published\n"
        }
      ],
      "capabilities" => ["workspace.read", "workspace.write"],
      "permissions" => %{"src" => ["replace_text"]}
    }

    approval = %{"request_digest" => digest(request), "capabilities" => request["capabilities"]}
    receipt = EditRuntime.Workflow.run(%{"request" => request, "approval" => approval})

    assert receipt.status == "denied"
    assert receipt.error == "folder docs does not allow replace_text"
    assert File.read!(Path.join(root, "docs/readme.txt")) == "draft\n"
    File.rm_rf!(root)
  end

  test "changed request is denied by the approval digest" do
    request = %{
      "version" => 1,
      "workspace_root" => "/tmp",
      "operations" => [],
      "permissions" => %{}
    }

    approval = %{"request_digest" => digest(request), "capabilities" => []}
    changed = Map.put(request, "operations", [%{"type" => "replace_text"}])

    receipt = EditRuntime.Workflow.run(%{"request" => changed, "approval" => approval})

    assert receipt.status == "denied"
    assert receipt.effects == []
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp digest(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
