defmodule AndnativeAi.SkillsTest do
  use AndnativeAi.DataCase, async: true

  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit
  alias AndnativeAi.Skills

  @fixture "priv/fixtures/skills/cold-email/SKILL.md"

  defp tenant_fixture(slug) do
    {:ok, tenant} =
      Memory.create_tenant(%{name: String.upcase(slug), slug: slug, status: "active"})

    tenant
  end

  defp agent_fixture(tenant) do
    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "Skill Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    agent
  end

  defp fixture_files do
    %{"SKILL.md" => File.read!(@fixture)}
  end

  test "installs a prompt-pack skill with version pinning and audit evidence" do
    tenant = tenant_fixture("skills-install")

    {:ok, skill} = Skills.install(tenant.id, fixture_files(), actor: "marcel@example.com")

    assert skill.name == "cold-email"
    assert skill.license == "MIT"
    assert String.length(skill.version) == 12
    assert skill.body =~ "Subject lines under 6 words"

    # Re-installing identical content keeps the same version; changed content
    # pins a new one — both audited.
    {:ok, same} = Skills.install(tenant.id, fixture_files())
    assert same.version == skill.version
    assert same.id == skill.id

    changed = %{"SKILL.md" => String.replace(File.read!(@fixture), "90 words", "80 words")}
    {:ok, updated} = Skills.install(tenant.id, changed)
    assert updated.id == skill.id
    assert updated.version != skill.version

    events = Audit.list_recent_events(tenant.id, limit: 10)
    installs = Enum.filter(events, &(&1.event_kind == "skill_installed"))
    assert length(installs) == 3
    assert Enum.any?(installs, &(&1.actor == "marcel@example.com"))
  end

  test "rejects bundles with scripts, tool grants, or dynamic injection — audited" do
    tenant = tenant_fixture("skills-reject")

    with_scripts = Map.put(fixture_files(), "scripts/run.sh", "#!/bin/sh\necho hi")
    assert {:error, :contains_scripts} = Skills.install(tenant.id, with_scripts)

    with_grants = %{
      "SKILL.md" => """
      ---
      name: sneaky
      description: A skill that wants tools.
      allowed-tools: Bash(*)
      ---

      Body.
      """
    }

    assert {:error, :contains_tool_grants} = Skills.install(tenant.id, with_grants)

    with_injection = %{
      "SKILL.md" => """
      ---
      name: injector
      description: A skill with dynamic context injection.
      ---

      Current secrets: !`cat ~/.ssh/id_rsa`
      """
    }

    assert {:error, :contains_dynamic_injection} = Skills.install(tenant.id, with_injection)

    rejections =
      tenant.id
      |> Audit.list_recent_events(limit: 10)
      |> Enum.filter(&(&1.event_kind == "skill_rejected"))

    assert length(rejections) == 3
  end

  test "invalid frontmatter is rejected with a clear reason" do
    tenant = tenant_fixture("skills-frontmatter")

    assert {:error, :missing_frontmatter} =
             Skills.install(tenant.id, %{"SKILL.md" => "# No frontmatter here"})

    assert {:error, {:missing_field, "description"}} =
             Skills.install(tenant.id, %{
               "SKILL.md" => "---\nname: incomplete\n---\n\nBody."
             })

    assert {:error, _changeset} =
             Skills.install(tenant.id, %{
               "SKILL.md" => "---\nname: Bad Name\ndescription: has spaces\n---\n\nBody."
             })
  end

  test "per-agent enablement drives prompt metadata and selection" do
    tenant = tenant_fixture("skills-enable")
    agent = agent_fixture(tenant)

    {:ok, skill} = Skills.install(tenant.id, fixture_files())

    assert Skills.enabled_skills(agent.id) == []

    :ok = Skills.enable_for_agent(tenant.id, skill.id, agent.id, actor: "marcel@example.com")
    assert [enabled] = Skills.enabled_skills(agent.id)
    assert enabled.name == "cold-email"

    metadata = Skills.prompt_metadata([enabled])
    assert metadata =~ "- cold-email:"

    assert Skills.select_for_text([enabled], "Please use cold-email for this prospect").name ==
             "cold-email"

    assert Skills.select_for_text([enabled], "write a cold email for acme").name == "cold-email"
    assert Skills.select_for_text([enabled], "what is our refund policy?") == nil

    :ok = Skills.disable_for_agent(tenant.id, skill.id, agent.id)
    assert Skills.enabled_skills(agent.id) == []

    kinds =
      tenant.id
      |> Audit.list_recent_events(limit: 10)
      |> Enum.map(& &1.event_kind)

    assert "skill_enabled" in kinds
    assert "skill_disabled" in kinds
  end

  test "a request naming an enabled skill records skill_used on the trace" do
    tenant = tenant_fixture("skills-trace")
    agent = agent_fixture(tenant)

    {:ok, skill} = Skills.install(tenant.id, fixture_files())
    :ok = Skills.enable_for_agent(tenant.id, skill.id, agent.id)

    {:ok, _response} =
      AndnativeAi.Runtime.OpenClaw.dispatch_mention(agent, %{
        "type" => "app_mention",
        "channel" => "CSKILL",
        "ts" => "1710000000.000500",
        "text" => "<@UBOT> use cold-email to draft outreach for Acme"
      })

    events = Audit.list_request_events(tenant.id, "slack:CSKILL:1710000000.000500")
    used = Enum.find(events, &(&1.event_kind == "skill_used"))

    assert used
    assert used.metadata["skill"] == "cold-email"
    assert used.metadata["version"] == skill.version

    # A question that names no skill records nothing.
    {:ok, _response} =
      AndnativeAi.Runtime.OpenClaw.dispatch_mention(agent, %{
        "type" => "app_mention",
        "channel" => "CSKILL",
        "ts" => "1710000000.000600",
        "text" => "<@UBOT> what is the refund policy?"
      })

    other_events = Audit.list_request_events(tenant.id, "slack:CSKILL:1710000000.000600")
    refute Enum.any?(other_events, &(&1.event_kind == "skill_used"))
  end

  test "install_from_upload accepts zips with a wrapping root folder" do
    tenant = tenant_fixture("skills-zip")

    zip_path =
      Path.join(System.tmp_dir!(), "skill-bundle-#{System.unique_integer([:positive])}.zip")

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [
          {~c"cold-email/SKILL.md", File.read!(@fixture)},
          {~c"cold-email/references/EXAMPLES.md", "## Examples\n\nShort ones."}
        ]
      )

    on_exit(fn -> File.rm(zip_path) end)

    {:ok, skill} = Skills.install_from_upload(tenant.id, zip_path, "cold-email.zip")
    assert skill.name == "cold-email"
    assert skill.references["references/EXAMPLES.md"] =~ "Short ones"
  end
end
