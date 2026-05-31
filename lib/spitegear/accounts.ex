defmodule Spitegear.Accounts do
  @moduledoc """
  Manages user accounts. Currently used only for admin HTTP basic auth.
  """

  import Ecto.Query
  alias Spitegear.Accounts.User
  alias Spitegear.Repo

  @doc "Returns the user with the given username, or nil."
  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Verifies a plaintext password against a user's stored hash.
  Always runs a hash comparison (even for nil users) to prevent timing attacks.
  """
  def verify_password(nil, _password) do
    Bcrypt.no_user_verify()
    false
  end

  def verify_password(%User{password_hash: hash}, password) do
    Bcrypt.verify_pass(password, hash)
  end

  @doc "Creates a new user with a hashed password."
  def create_user(username, password) do
    %User{}
    |> User.registration_changeset(%{username: username, password: password})
    |> Repo.insert()
  end

  @doc "Lists all usernames."
  def list_usernames do
    Repo.all(from(u in User, select: u.username, order_by: u.username))
  end
end
