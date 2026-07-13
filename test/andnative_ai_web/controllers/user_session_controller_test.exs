defmodule AndnativeAiWeb.UserSessionControllerTest do
  use AndnativeAiWeb.ConnCase, async: false

  import AndnativeAi.AccountsFixtures

  alias AndnativeAi.Accounts
  alias AndnativeAi.Memory
  alias AndnativeAi.Runtime.Audit

  describe "platform access auditing (AAI-34)" do
    test "superadmin login lands on the governance trail; admin login does not", %{conn: conn} do
      password = valid_user_password()
      admin = user_fixture(%{password: password})

      {:ok, superadmin} =
        Accounts.set_user_role(user_fixture(%{password: password}), "superadmin")

      tenant = Memory.ensure_demo_tenant!()

      conn
      |> post(~p"/login", %{"user" => %{"email" => admin.email, "password" => password}})

      refute Enum.any?(
               Audit.list_recent_events(tenant.id, limit: 10),
               &(&1.event_kind == "platform_access")
             )

      build_conn()
      |> post(~p"/login", %{"user" => %{"email" => superadmin.email, "password" => password}})

      assert Enum.any?(
               Audit.list_recent_events(tenant.id, limit: 10),
               &(&1.event_kind == "platform_access" and &1.actor == superadmin.email)
             )
    end
  end
end
