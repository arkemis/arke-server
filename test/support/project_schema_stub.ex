defmodule ArkeServer.Support.ProjectSchemaStub do
  @moduledoc """
  Sandbox-safe stand-in for the ArkePostgres project DDL.

  `Ecto.Migrator.run` checks out its own connection, which the SQL sandbox
  refuses, so real schema creation cannot run inside a test transaction.
  Before the persistence layer surfaced errors this failure was silent; now
  it would fail every project-controller test, so the DDL is stubbed out.
  """

  def create_project(_unit), do: :ok
  def delete_project(_unit), do: :ok
end
