# Copyright 2023 Arkemis S.r.l.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule ArkeServer.Utils.ExistingAtom do
  @moduledoc """
  Converts client input to an atom only when that atom already exists.

  Atoms are never garbage collected and the VM has a fixed atom limit, so
  `String.to_atom/1` on request data lets a client exhaust it and crash the
  node. An input that names no existing atom cannot name an arke, a
  parameter or a function either, so it is safe to treat it as unknown.
  """

  @doc "Returns the existing atom for `value`, or `nil`."
  @spec get(term()) :: atom() | nil
  def get(value) when is_atom(value), do: value

  def get(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  def get(_value), do: nil
end
