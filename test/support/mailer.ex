defmodule ArkeServer.TestMailer do
  @moduledoc """
  Mailer for the test suite.

  `ArkeServer.Mailer` supplies no-op `signin/3`, `signup/3` and `reset_password/3`, which
  is all the auth flows need. Consumer apps provide their own module and point
  `:mailer_module` at it; without one the auth controller calls `nil.signup/3`.
  """
  use ArkeServer.Mailer
end
