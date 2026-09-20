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

    case cmd(
           agent,
           {EditRuntime.PlanAction,
            %{request: Jason.encode!(request), approval: Jason.encode!(approval)}}
         ) do
      {%{state: %{plan: plan}}, []} when map_size(plan) > 0 -> {:ok, plan}
      {_agent, directives} -> {:error, directive_message(directives)}
    end
  end

  defp directive_message(directives) do
    directives
    |> Enum.find_value("plan failed", fn
      %Jido.Agent.Directive.Error{error: error} -> action_message(error)
      _ -> nil
    end)
  end

  defp action_message(%{details: %{reason: %{message: message}}}), do: message
  defp action_message(%{message: message}), do: message
  defp action_message(other), do: inspect(other)
end

defmodule EditRuntime.Workflow do
  def run(%{"request" => request, "approval" => approval}) do
    with {:ok, plan} <- safe_plan(request, approval),
         :ok <- authorize(plan),
         :ok <- authorize_folders(plan),
         {:ok, writes} <- prepare(plan),
         {:ok, judgment} <- judge(plan),
         {:ok, effects} <- apply_writes(writes),
         {:ok, verification} <- verify_or_restore(plan, writes) do
      receipt(plan, "succeeded", effects, verification, judgment)
    else
      {:error, reason} ->
        %{status: "denied", error: reason, effects: [], verification: %{status: "not_run"}}
    end
  end

  def run(_request), do: %{status: "failed", error: "request and approval are required"}

  defp safe_plan(request, approval) do
    EditRuntime.WorkflowAgent.plan(request, approval)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp prepare(plan) do
    request = plan[:request] || plan["request"]
    root = workspace_root(request)

    with {:ok, _} <- safe_path(root, verification_path(request)) do
      Enum.reduce_while(request["operations"] || [], {:ok, []}, fn operation, {:ok, writes} ->
        case prepare_operation(root, operation) do
          {:ok, write} -> {:cont, {:ok, writes ++ [write]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp prepare_operation(root, %{"type" => "replace_text"} = operation) do
    with {:ok, path} <- safe_path(root, operation["path"]),
         {:ok, current} <- read_file(path),
         true <- current == operation["expected"] || {:error, "expected content did not match"} do
      {:ok,
       %{
         path: path,
         relative: operation["path"],
         original: current,
         replacement: operation["replacement"]
       }}
    end
  end

  defp prepare_operation(_root, _operation), do: {:error, "unsupported operation"}

  defp apply_writes(writes) do
    Enum.each(writes, fn write -> File.write!(write.path, write.replacement) end)
    {:ok, Enum.map(writes, fn write -> %{type: "write", path: write.relative} end)}
  rescue
    error ->
      restore(writes)
      {:error, Exception.message(error)}
  end

  defp verify_or_restore(plan, writes) do
    request = plan[:request] || plan["request"]

    case verify(request["verification"], workspace_root(request)) do
      {:ok, verification} ->
        {:ok, verification}

      {:error, reason} ->
        restore(writes)
        {:error, reason}
    end
  end

  defp restore(writes) do
    Enum.each(writes, fn write -> File.write!(write.path, write.original) end)
  end

  defp verify(%{"type" => "file_equals", "path" => path, "expected" => expected}, root) do
    with {:ok, full_path} <- safe_path(root, path),
         {:ok, content} <- read_file(full_path) do
      if content == expected do
        {:ok, %{status: "passed", type: "file_equals", path: path}}
      else
        {:error, "verification content mismatch"}
      end
    end
  end

  defp verify(_, _), do: {:error, "unsupported verification"}

  defp verification_path(%{"verification" => %{"path" => path}}), do: path
  defp verification_path(_), do: "."

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp workspace_root(request) do
    Path.expand(request["workspace_root"] || request["workspaceRoot"])
  end

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

  defp authorize_folders(plan) do
    request = plan[:request] || plan["request"]
    approval = plan[:approval] || plan["approval"]
    permissions = request["permissions"] || %{}

    cond do
      permissions == %{} ->
        {:error, "permissions are required"}

      Map.has_key?(approval, "permissions") and approval["permissions"] != permissions ->
        {:error, "approval permissions do not match request"}

      true ->
        Enum.reduce_while(request["operations"] || [], :ok, fn operation, :ok ->
          case folder_allows?(permissions, operation) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp folder_allows?(permissions, operation) do
    path = operation["path"] || ""
    command = operation["type"]
    folder = folder_for(path)
    allowed = allowed_commands(permissions, folder, path)

    if command in allowed do
      :ok
    else
      {:error, "folder #{folder} does not allow #{command}"}
    end
  end

  defp folder_for(path) do
    case Path.dirname(path) do
      "." -> "."
      dir -> dir
    end
  end

  defp allowed_commands(permissions, folder, path) do
    permissions
    |> Enum.filter(fn {granted_folder, _commands} ->
      folder_covers?(granted_folder, folder, path)
    end)
    |> Enum.flat_map(fn {_folder, commands} -> List.wrap(commands) end)
  end

  defp folder_covers?(".", _folder, _path), do: true

  defp folder_covers?(granted, folder, path) do
    granted == folder or granted == path or String.starts_with?(path, granted <> "/")
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
      (System.get_env("AI_GATEWAY_TOKEN") not in [nil, ""] and
         System.get_env("CLOUDFLARE_ACCOUNT_ID") not in [nil, ""])
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_exception(reason), do: Exception.message(reason)
  defp format_error(reason), do: inspect(reason)

  defp safe_path(_root, relative) when not is_binary(relative), do: {:error, "path is required"}

  defp safe_path(root, relative) do
    expanded = Path.expand(relative, root)

    cond do
      Path.type(relative) == :absolute ->
        {:error, "path escapes workspace"}

      expanded != root and not String.starts_with?(expanded, root <> "/") ->
        {:error, "path escapes workspace"}

      symlink_in_path?(root, expanded) ->
        {:error, "path crosses a symlink"}

      hard_link?(expanded) ->
        {:error, "path has extra hard links"}

      true ->
        {:ok, expanded}
    end
  end

  defp hard_link?(path) do
    match?({:ok, %File.Stat{links: links}} when links > 1, File.lstat(path))
  end

  defp symlink_in_path?(root, expanded) do
    expanded
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.scan(root, &Path.join(&2, &1))
    |> Enum.any?(fn component ->
      match?({:ok, %File.Stat{type: :symlink}}, File.lstat(component))
    end)
  end
end
