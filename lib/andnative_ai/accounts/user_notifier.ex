defmodule AndnativeAi.Accounts.UserNotifier do
  @moduledoc """
  Transactional emails for the admin auth flows (password reset, invitations).
  """

  import Swoosh.Email

  alias AndnativeAi.Mailer

  # Delivers the email through the configured Swoosh adapter.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:andnative_ai, :mailer_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Delivers password-reset instructions with the reset URL.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your &native.ai password", """

    Hi #{user.email},

    You can reset your &native.ai admin password by visiting the link below:

    #{url}

    If you didn't request this, you can safely ignore this email.
    """)
  end

  @doc """
  Delivers an invitation with the activation URL.
  """
  def deliver_invitation(user, url) do
    deliver(user.email, "You're invited to the &native.ai admin", """

    Hi #{user.email},

    You've been invited to the &native.ai admin. Set your password and activate
    your account by visiting the link below:

    #{url}

    If you weren't expecting this, you can ignore this email.
    """)
  end
end
