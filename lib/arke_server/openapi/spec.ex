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

defmodule ArkeServer.Openapi.Spec do
  @doc """
  For each controller define the module containing its apispec definitions.
  In your controller module:
      use ArkeServer.Openapi.Spec, module: My.Spec.Module
  """
  defmacro __using__(opts) do
    case Keyword.get(opts, :module, nil) do
      nil ->
        quote do
          def open_api_operation(_action), do: nil
        end

      apimodule ->
        quote do
          def open_api_operation(action) do
            operation = "#{action}_operation"

            func_list =
              unquote(apimodule).__info__(:functions)
              |> Enum.map(fn {func_name, _arity} -> to_string(func_name) end)

            if operation in func_list do
              apply(unquote(apimodule), String.to_existing_atom(operation), [])
            end
          end
        end
    end
  end
end
