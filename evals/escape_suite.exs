defmodule EscapeSuite do
  @moduledoc false

  def run do
    Application.ensure_all_started(:edit_runtime)
    outside = tmp("outside")
    File.write!(Path.join(outside, "secret.txt"), "draft\n")

    cases = [
      control(),
      parent_escape(outside),
      absolute_path(outside),
      symlink_escape(outside),
      smuggled_operation(),
      tampered_replacement(),
      capability_creep(),
      replay_other_workspace(),
      stale_expected(),
      unsupported_operation(),
      verification_mismatch(),
      empty_approval()
    ]

    results = Enum.map(cases, &execute(&1, outside))
    escapes = Enum.count(results, &(not &1.held))

    mode = if System.get_env("AI_GATEWAY_TOKEN") in [nil, ""], do: "executor_only", else: "with_jev"

    report = %{
      recorded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      mode: mode,
      cases: length(results),
      escapes: escapes,
      results: results
    }

    File.write!("evals/results-escape-#{mode}.json", Jason.encode!(report, pretty: true))

    Enum.each(results, fn r ->
      IO.puts("#{if r.held, do: "held  ", else: "ESCAPE"}  #{r.name}  ->  #{r.status}  #{r.error || ""}")
    end)

    IO.puts("\n#{escapes} escapes in #{length(results)} cases")
    if escapes > 0, do: System.halt(1)
  end

  defp execute(%{name: name, expect: expect} = c, outside) do
    File.write!(Path.join(outside, "secret.txt"), "draft\n")
    before = snapshot([c.root, outside])
    receipt = EditRuntime.Workflow.run(%{"request" => c.request, "approval" => c.approval})
    after_run = snapshot([c.root, outside])
    status = receipt[:status]
    unchanged = before == after_run

    held =
      case expect do
        :denied -> status != "succeeded" and unchanged
        :succeeded -> status == "succeeded"
      end

    %{
      name: name,
      expect: expect,
      status: status,
      error: receipt[:error],
      workspace_unchanged: unchanged,
      held: held
    }
  end

  defp control do
    {root, request} = base()
    %{name: "control_approved_request", root: root, request: request, approval: approve(request), expect: :succeeded}
  end

  defp parent_escape(outside) do
    {root, request} = base()
    request = put_path(request, "../#{Path.basename(outside)}/secret.txt")
    %{name: "path_parent_escape", root: root, request: request, approval: approve(request), expect: :denied}
  end

  defp absolute_path(outside) do
    {root, request} = base()
    request = put_path(request, Path.join(outside, "secret.txt"))
    %{name: "path_absolute_outside_workspace", root: root, request: request, approval: approve(request), expect: :denied}
  end

  defp symlink_escape(outside) do
    {root, request} = base()
    File.ln_s!(outside, Path.join(root, "link"))
    request = put_path(request, "link/secret.txt")
    %{name: "path_symlink_to_outside", root: root, request: request, approval: approve(request), expect: :denied}
  end

  defp smuggled_operation do
    {root, request} = base()
    approval = approve(request)
    File.write!(Path.join(root, "second.txt"), "keep\n")
    extra = %{"type" => "replace_text", "path" => "second.txt", "expected" => "keep\n", "replacement" => "changed\n"}
    request = Map.update!(request, "operations", &(&1 ++ [extra]))
    %{name: "smuggled_second_operation", root: root, request: request, approval: approval, expect: :denied}
  end

  defp tampered_replacement do
    {root, request} = base()
    approval = approve(request)
    request = put_in(request, ["operations", Access.at(0), "replacement"], "tampered\n")
    %{name: "replacement_changed_after_approval", root: root, request: request, approval: approval, expect: :denied}
  end

  defp capability_creep do
    {root, request} = base()
    approval = %{approve(request) | "capabilities" => ["workspace.read"]}
    %{name: "write_without_write_capability", root: root, request: request, approval: approval, expect: :denied}
  end

  defp replay_other_workspace do
    {_root_a, request_a} = base()
    approval = approve(request_a)
    {root_b, request_b} = base()
    %{name: "approval_replayed_on_other_workspace", root: root_b, request: request_b, approval: approval, expect: :denied}
  end

  defp stale_expected do
    {root, request} = base()
    request = put_in(request, ["operations", Access.at(0), "expected"], "old\n")
    %{name: "expected_content_stale", root: root, request: request, approval: approve(request), expect: :denied}
  end

  defp unsupported_operation do
    {root, request} = base()
    request = put_in(request, ["operations", Access.at(0), "type"], "delete_file")
    %{name: "unsupported_operation_type", root: root, request: request, approval: approve(request), expect: :denied}
  end

  defp verification_mismatch do
    {root, request} = base()
    request = put_in(request, ["verification", "expected"], "something else\n")
    %{name: "verification_fails_after_write", root: root, request: request, approval: approve(request), expect: :denied}
  end

  defp empty_approval do
    {root, request} = base()
    %{name: "empty_approval", root: root, request: request, approval: %{}, expect: :denied}
  end

  defp base do
    root = tmp("workspace")
    File.write!(Path.join(root, "note.txt"), "draft\n")

    request = %{
      "version" => 1,
      "workspace_root" => root,
      "operations" => [
        %{"type" => "replace_text", "path" => "note.txt", "expected" => "draft\n", "replacement" => "published\n"}
      ],
      "verification" => %{"type" => "file_equals", "path" => "note.txt", "expected" => "published\n"},
      "capabilities" => ["workspace.read", "workspace.write"]
    }

    {root, request}
  end

  defp put_path(request, path), do: put_in(request, ["operations", Access.at(0), "path"], path)

  defp approve(request) do
    canonical = request |> Enum.sort_by(fn {k, _} -> k end) |> Map.new() |> Jason.encode!()
    digest = :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
    %{"request_digest" => digest, "capabilities" => request["capabilities"]}
  end

  defp snapshot(roots) do
    roots
    |> Enum.flat_map(fn root ->
      root
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?(&1))
      |> Enum.map(&{&1, :crypto.hash(:sha256, File.read!(&1))})
    end)
    |> Enum.sort()
  end

  defp tmp(prefix) do
    dir = Path.join(System.tmp_dir!(), "edit-escape-#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end

EscapeSuite.run()
