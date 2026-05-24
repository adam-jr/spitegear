defmodule Mix.Tasks.Spitegear.CreateUser do
  @shortdoc "Create an admin user: mix spitegear.create_user <username> <password>"
  @moduledoc @shortdoc

  use Mix.Task

  @requirements ["app.start"]

  def run([username, password]) do
    case Spitegear.Accounts.create_user(username, password) do
      {:ok, user} -> Mix.shell().info("✓ Created user: #{user.username}")
      {:error, changeset} -> Mix.shell().error("Failed: #{format_errors(changeset)}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix spitegear.create_user <username> <password>")
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&interpolate_error/1)
    |> inspect()
  end

  defp interpolate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
