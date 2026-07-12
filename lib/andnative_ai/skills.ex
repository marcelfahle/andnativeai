defmodule AndnativeAi.Skills do
  @moduledoc """
  Governed prompt-pack skills (Agent Skills standard, phase 1): installed
  per tenant, enabled per agent, version-pinned by content hash, and every
  install/enable/disable/removal — and every rejected bundle — is audit
  evidence.
  """

  import Ecto.Query

  alias AndnativeAi.Repo
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Skills.{Parser, Skill}

  @doc """
  Installs (or re-installs, version-pinned) a skill from a parsed bundle of
  `path => content`. Rejections are audited as `skill_rejected`.
  """
  def install(tenant_id, files, opts \\ []) do
    actor = Keyword.get(opts, :actor, "Admin")

    case Parser.parse(files) do
      {:ok, parsed} ->
        version = version_hash(parsed)

        result =
          case Repo.get_by(Skill, tenant_id: tenant_id, name: parsed.name) do
            nil -> %Skill{tenant_id: tenant_id}
            %Skill{} = existing -> existing
          end
          |> Skill.changeset(%{
            name: parsed.name,
            description: parsed.description,
            body: parsed.body,
            references: parsed.references,
            version: version,
            license: parsed.license,
            compatibility: parsed.compatibility,
            source_url: Keyword.get(opts, :source_url)
          })
          |> Repo.insert_or_update()

        case result do
          {:ok, skill} ->
            record_event(tenant_id, "skill_installed", %{
              actor: actor,
              status: "installed",
              summary: "Skill \"#{skill.name}\" v#{skill.version} was installed.",
              metadata: %{skill: skill.name, version: skill.version, license: skill.license}
            })

            {:ok, skill}

          {:error, changeset} ->
            record_event(tenant_id, "skill_rejected", %{
              actor: actor,
              status: "rejected",
              summary: "A skill bundle was rejected: invalid skill attributes.",
              metadata: %{reason: Audit.reason_summary(changeset.errors)}
            })

            {:error, changeset}
        end

      {:error, reason} ->
        record_event(tenant_id, "skill_rejected", %{
          actor: actor,
          status: "rejected",
          summary: "A skill bundle was rejected: #{reject_reason(reason)}.",
          metadata: %{reason: Audit.reason_summary(reason)}
        })

        {:error, reason}
    end
  end

  @doc "Installs from an uploaded `.zip` bundle or a bare `SKILL.md` file."
  def install_from_upload(tenant_id, path, filename, opts \\ []) do
    case Path.extname(filename) do
      ".zip" ->
        with {:ok, files} <- read_zip(path) do
          install(tenant_id, files, opts)
        end

      ".md" ->
        with {:ok, content} <- File.read(path) do
          install(tenant_id, %{"SKILL.md" => content}, opts)
        end

      _other ->
        {:error, :unsupported_file_type}
    end
  end

  def list_skills(tenant_id) do
    Repo.all(from skill in Skill, where: skill.tenant_id == ^tenant_id, order_by: skill.name)
  end

  def get_skill!(tenant_id, id), do: Repo.get_by!(Skill, id: id, tenant_id: tenant_id)

  def remove_skill(tenant_id, id, opts \\ []) do
    skill = get_skill!(tenant_id, id)
    {:ok, _} = Repo.delete(skill)

    record_event(tenant_id, "skill_removed", %{
      actor: Keyword.get(opts, :actor, "Admin"),
      status: "removed",
      summary: "Skill \"#{skill.name}\" was removed.",
      metadata: %{skill: skill.name, version: skill.version}
    })

    {:ok, skill}
  end

  def enable_for_agent(tenant_id, skill_id, agent_id, opts \\ []) do
    skill = get_skill!(tenant_id, skill_id)
    # Raises unless the agent belongs to the same tenant — no cross-tenant
    # skill leakage.
    agent = AndnativeAi.Memory.get_agent!(tenant_id, agent_id)

    Repo.insert_all(
      "agent_skills",
      [
        [
          agent_id: agent.id,
          skill_id: skill.id,
          inserted_at: utc_now(),
          updated_at: utc_now()
        ]
      ],
      on_conflict: :nothing,
      conflict_target: [:agent_id, :skill_id]
    )

    record_event(tenant_id, "skill_enabled", %{
      actor: Keyword.get(opts, :actor, "Admin"),
      agent_id: agent_id,
      status: "enabled",
      summary: "Skill \"#{skill.name}\" v#{skill.version} was enabled for the agent.",
      metadata: %{skill: skill.name, version: skill.version}
    })

    :ok
  end

  def disable_for_agent(tenant_id, skill_id, agent_id, opts \\ []) do
    skill = get_skill!(tenant_id, skill_id)
    agent = AndnativeAi.Memory.get_agent!(tenant_id, agent_id)
    agent_id = agent.id

    Repo.delete_all(
      from(join in "agent_skills",
        where: join.agent_id == ^agent_id and join.skill_id == ^skill_id
      )
    )

    record_event(tenant_id, "skill_disabled", %{
      actor: Keyword.get(opts, :actor, "Admin"),
      agent_id: agent_id,
      status: "disabled",
      summary: "Skill \"#{skill.name}\" was disabled for the agent.",
      metadata: %{skill: skill.name, version: skill.version}
    })

    :ok
  end

  def enabled_skills(agent_id) do
    Repo.all(
      from skill in Skill,
        join: join in "agent_skills",
        on: join.skill_id == skill.id,
        where: join.agent_id == ^agent_id,
        order_by: skill.name
    )
  end

  def enabled_skill_ids(agent_id) do
    Repo.all(
      from join in "agent_skills", where: join.agent_id == ^agent_id, select: join.skill_id
    )
  end

  @doc """
  Progressive disclosure, stage 1: the ~100-token metadata line per enabled
  skill for the agent's system prompt.
  """
  def prompt_metadata(skills) do
    Enum.map_join(skills, "\n", fn skill -> "- #{skill.name}: #{skill.description}" end)
  end

  @doc """
  Picks the enabled skill a question explicitly names, if any — stage 2 of
  progressive disclosure loads its body. Deterministic on purpose in
  phase 1.
  """
  def select_for_text(skills, text) when is_binary(text) do
    normalized = String.downcase(text)

    Enum.find(skills, fn skill ->
      String.contains?(normalized, skill.name) or
        String.contains?(normalized, String.replace(skill.name, "-", " "))
    end)
  end

  def select_for_text(_skills, _text), do: nil

  @doc "Audits which skill+version shaped an answer, on the request trace."
  def record_skill_used(tenant_id, agent_id, request_id, skill) do
    record_event(tenant_id, "skill_used", %{
      agent_id: agent_id,
      request_id: request_id,
      actor: "Runtime",
      status: "used",
      summary: "Skill \"#{skill.name}\" v#{skill.version} shaped this response.",
      metadata: %{skill: skill.name, version: skill.version}
    })
  end

  defp version_hash(parsed) do
    content =
      [parsed.body | parsed.references |> Enum.sort() |> Enum.map(fn {k, v} -> k <> v end)]
      |> Enum.join("\n")

    :sha256
    |> :crypto.hash(parsed.name <> "\n" <> parsed.description <> "\n" <> content)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end

  defp read_zip(path) do
    with {:ok, entries} <- :zip.unzip(String.to_charlist(path), [:memory]) do
      files =
        entries
        |> Enum.map(fn {name, content} -> {to_string(name), content} end)
        |> Enum.reject(fn {name, _content} -> unsafe_entry_name?(name) end)
        |> Map.new()

      {:ok, strip_common_root(files)}
    end
  end

  # Bundles are often zipped with a wrapping directory (skill-name/SKILL.md).
  # When SKILL.md is not at the root but every entry shares one root folder
  # containing it, strip that root; flat bundles pass through untouched.
  defp strip_common_root(files) do
    if Map.has_key?(files, "SKILL.md") do
      files
    else
      roots =
        files |> Map.keys() |> Enum.map(&(&1 |> Path.split() |> List.first())) |> Enum.uniq()

      case roots do
        [root] when is_binary(root) ->
          stripped =
            Map.new(files, fn {name, content} ->
              case Path.split(name) do
                [_root] -> {name, content}
                [_root | rest] -> {Path.join(rest), content}
              end
            end)

          if Map.has_key?(stripped, "SKILL.md"), do: stripped, else: files

        _multiple ->
          files
      end
    end
  end

  defp unsafe_entry_name?(name) do
    segments = Path.split(name)

    Path.type(name) != :relative or
      Enum.any?(segments, fn segment ->
        segment == ".." or String.starts_with?(segment, ".")
      end)
  end

  defp reject_reason(:contains_scripts), do: "bundle contains executable scripts"
  defp reject_reason(:contains_tool_grants), do: "bundle requests tool grants"
  defp reject_reason(:contains_dynamic_injection), do: "bundle contains dynamic shell injection"
  defp reject_reason(:missing_skill_md), do: "no SKILL.md found"
  defp reject_reason(:missing_frontmatter), do: "SKILL.md has no frontmatter"
  defp reject_reason({:missing_field, field}), do: "frontmatter is missing #{field}"
  defp reject_reason(other), do: inspect(other)

  defp record_event(tenant_id, event_kind, overrides) do
    attrs =
      Map.merge(
        %{
          tenant_id: tenant_id,
          event_kind: event_kind,
          component: "skills_library",
          actor: "Admin",
          status: "",
          summary: "",
          metadata: %{}
        },
        Map.new(overrides)
      )

    case Application.get_env(:andnative_ai, :audit_recorder, Audit) do
      recorder when is_function(recorder, 1) -> recorder.(attrs)
      recorder -> recorder.record_best_effort(attrs)
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
