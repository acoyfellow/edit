defmodule EditRuntime.PlanAction do
  use Jido.Action,
    name: "plan_edit",
    description: "Validate an approved edit request",
    schema: [request: [type: :string, required: true], approval: [type: :string, required: true]]

  def run(%{request: request_json, approval: approval_json}, _context) do
    with {:ok, request} <- Jason.decode(request_json),
         {:ok, approval} <- Jason.decode(approval_json) do
      request_digest = digest(request)

      if request_digest == approval["request_digest"] do
        {:ok, %{plan: %{request: request, approval: approval, request_digest: request_digest}}}
      else
        {:error, "approval does not match request"}
      end
    end
  end

  defp digest(value) do
    value
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
    |> Jason.encode!()
  end
end

defmodule EditRuntime.WorkflowAgent do
  use Jido.Agent,
    name: "edit_workflow",
    description: "Coordinates an approved bounded edit",
    schema: [plan: [type: :map, default: %{}]]

  def plan(request, approval) do
    agent = new()

    {agent, []} =
      cmd(
        agent,
        {EditRuntime.PlanAction,
         %{request: Jason.encode!(request), approval: Jason.encode!(approval)}}
      )

    agent.state.plan
  end
end

defmodule EditRuntime.Workflow do
  def run(%{"request" => request, "approval" => approval}) do
    with {:ok, plan} <- safe_plan(request, approval),
         :ok <- authorize(plan),
         {:ok, judgment} <- judge(plan),
         {:ok, effects} <- execute(plan),
         {:ok, verification} <-
           verify(request_value(plan, "verification"), request_value(plan, "workspace_root")) do
      receipt(plan, "succeeded", effects, verification, judgment)
    else
      {:error, reason} ->
        %{status: "denied", error: reason, effects: [], verification: %{status: "not_run"}}
    end
  end

  def run(_request), do: %{status: "failed", error: "request and approval are required"}

  defp safe_plan(request, approval) do
    {:ok, EditRuntime.WorkflowAgent.plan(request, approval)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp execute(plan) do
    request = plan[:request] || plan["request"]
    root = Path.expand(request["workspace_root"] || request["workspaceRoot"])

    Enum.reduce_while(request["operations"] || [], {:ok, []}, fn operation, {:ok, effects} ->
      case operation["type"] do
        "replace_text" ->
          path = safe_path(root, operation["path"])

          with {:ok, old} <- File.read(path), true <- old == operation["expected"] do
            File.write!(path, operation["replacement"])
            {:cont, {:ok, [%{type: "write", path: operation["path"]} | effects]}}
          else
            false -> {:halt, {:error, "expected content did not match"}}
            {:error, reason} -> {:halt, {:error, format_error(reason)}}
          end

        _ ->
          {:halt, {:error, "unsupported operation"}}
      end
    end)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp verify(%{"type" => "file_equals", "path" => path, "expected" => expected}, root) do
    case File.read(safe_path(Path.expand(root), path)) do
      {:ok, ^expected} -> {:ok, %{status: "passed", type: "file_equals", path: path}}
      {:ok, _} -> {:error, "verification content mismatch"}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp verify(_, _), do: {:error, "unsupported verification"}

  defp authorize(plan) do
    request = plan[:request] || plan["request"]
    approval = plan[:approval] || plan["approval"]
    requested = MapSet.new(request["capabilities"] || [])
    granted = MapSet.new(approval["capabilities"] || [])

    if MapSet.subset?(requested, granted) do
      :ok
    else
      {:error, "approval does not grant every requested capability"}
    end
  end

  defp judge(plan) do
    if jev_credentials_available?() do
      case EditRuntime.Judgment.approve?(plan) do
        {:ok, decision} when decision in [:approve, "approve"] ->
          {:ok, %{status: "approved", decision: decision}}

        {:ok, decision} ->
          {:error, "jev rejected edit: #{inspect(decision)}"}

        {:error, reason} ->
          {:error, format_error(reason)}
      end
    else
      {:ok, %{status: "blocked_missing_credentials"}}
    end
  rescue
    error -> {:error, format_error(error)}
  end

  defp receipt(plan, status, effects, verification, judgment) do
    request = plan[:request] || plan["request"]

    %{
      status: status,
      request_digest: plan[:request_digest],
      effects: effects,
      verification: verification,
      jido: "edit_workflow",
      jev: judgment,
      request: request
    }
  end

  defp jev_credentials_available? do
    System.get_env("TYPESAFE_API_KEY") not in [nil, ""] or
      (System.get_env("CLOUDFLARE_API_TOKEN") not in [nil, ""] and
         System.get_env("CLOUDFLARE_ACCOUNT_ID") not in [nil, ""])
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_error(reason), do: inspect(reason)

  defp safe_path(root, relative) do
    expanded = Path.expand(relative, root)
    relative_path = Path.relative_to(expanded, root)

    if relative_path == ".." or String.starts_with?(relative_path, "../") do
      raise("path escapes workspace")
    end

    expanded
  end

  defp request_value(plan, key) do
    request = plan[:request] || plan["request"]
    request[key] || request[camelize_key(key)]
  end

  defp camelize_key("workspace_root"), do: "workspaceRoot"
  defp camelize_key(key), do: key
end
