defmodule AndnativeAiWeb.Admin.SkillsLiveTest do
  use AndnativeAiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AndnativeAi.Memory
  alias AndnativeAi.Skills

  setup :register_and_log_in_user

  test "installs a skill from upload, toggles it per agent, and removes it", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    {:ok, agent} =
      Memory.create_agent(tenant.id, %{
        name: "UI Agent",
        identity: "Answer from governed memory.",
        model: "gpt-4.1-mini",
        runtime: "openclaw",
        status: "active"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/skills")
    assert has_element?(view, "#skills-empty")

    view
    |> file_input("#skill-install-form", :skill_bundle, [
      %{
        name: "SKILL.md",
        content: File.read!("priv/fixtures/skills/cold-email/SKILL.md"),
        type: "text/markdown"
      }
    ])
    |> render_upload("SKILL.md")

    view |> form("#skill-install-form") |> render_submit()

    assert [skill] = Skills.list_skills(tenant.id)
    assert has_element?(view, "#skill-#{skill.id}", "cold-email")
    assert has_element?(view, "#skill-#{skill.id}", "MIT")

    view
    |> element("#skill-#{skill.id}-agent-#{agent.id}")
    |> render_click()

    assert [%{name: "cold-email"}] = Skills.enabled_skills(agent.id)

    view
    |> element("#remove-skill-#{skill.id}")
    |> render_click()

    assert Skills.list_skills(tenant.id) == []
    assert has_element?(view, "#skills-empty")
  end

  test "rejects a scripted bundle with a clear flash", %{conn: conn} do
    tenant = Memory.ensure_demo_tenant!()

    zip_path =
      Path.join(System.tmp_dir!(), "bad-skill-#{System.unique_integer([:positive])}.zip")

    {:ok, _} =
      :zip.create(
        String.to_charlist(zip_path),
        [
          {~c"SKILL.md", File.read!("priv/fixtures/skills/cold-email/SKILL.md")},
          {~c"scripts/run.sh", "#!/bin/sh\necho pwned"}
        ]
      )

    on_exit(fn -> File.rm(zip_path) end)

    {:ok, view, _html} = live(conn, ~p"/admin/skills")

    view
    |> file_input("#skill-install-form", :skill_bundle, [
      %{name: "bad-skill.zip", content: File.read!(zip_path), type: "application/zip"}
    ])
    |> render_upload("bad-skill.zip")

    html = view |> form("#skill-install-form") |> render_submit()

    assert html =~ "executable scripts"
    assert Skills.list_skills(tenant.id) == []
  end
end
