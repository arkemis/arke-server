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

defmodule ArkeServer.Utils.QueryFilters do
  alias Arke.QueryManager
  alias Arke.Core.Query.{Filter, BaseFilter}
  alias Arke.Utils.ErrorGenerator, as: Error

  def apply_query_filters(query, {logic, negate, filters}) when is_list(filters) do
    apply_filter(query, logic, negate, filters)
  end

  def apply_query_filters(query, _filters), do: query

  def apply_member_child_only(query, member, true) when not is_nil(member) do
    QueryManager.link(query, member, depth: 10)
  end

  def apply_member_child_only(query, _, _), do: query

  defp apply_filter(query, :and, negate, filters), do: QueryManager.and_(query, negate, filters)
  defp apply_filter(query, :or, negate, filters), do: QueryManager.or_(query, negate, filters)

  def get_from_string(_conn, nil), do: {:ok, nil}

  def get_from_string(conn, filter_string) do
    case parse_node(conn, String.trim(filter_string)) do
      {:ok, %Filter{logic: logic, negate: negate, base_filters: filters}} ->
        {:ok, {logic, negate, filters}}

      {:ok, %BaseFilter{} = bf} ->
        {:ok, {:and, false, [bf]}}

      {:error, _} = error ->
        error
    end
  end

  # Recursively parse a filter expression node.
  # Returns {:ok, %Filter{}} for logical groups (and/or),
  # {:ok, %BaseFilter{}} for comparison operators.
  defp parse_node(conn, "and(" <> _ = str) do
    with {:ok, inner} <- extract_inner(str), do: parse_logical_node(conn, inner, :and)
  end

  defp parse_node(conn, "or(" <> _ = str) do
    with {:ok, inner} <- extract_inner(str), do: parse_logical_node(conn, inner, :or)
  end

  defp parse_node(conn, "not(" <> _ = str) do
    with {:ok, inner} <- extract_inner(str) do
      case parse_node(conn, inner) do
        {:ok, %Filter{} = filter} ->
          {:ok, %Filter{filter | negate: true}}

        {:ok, %BaseFilter{} = bf} ->
          {:ok, %BaseFilter{bf | negate: true}}

        error ->
          error
      end
    end
  end

  defp parse_node(conn, str) do
    case get_operator(str) do
      {:ok, operator} ->
        with {:ok, inner} <- extract_inner(str) do
          format_parameter_and_value(conn, inner, operator)
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_logical_node(conn, inner, logic) do
    parts = split_top_level(inner)

    results =
      Enum.map(parts, fn part ->
        parse_node(conn, String.trim(part))
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors != [] do
      {:error, Enum.flat_map(errors, fn {:error, msg} -> List.wrap(msg) end)}
    else
      filters = Enum.map(results, fn {:ok, filter} -> filter end)
      {:ok, %Filter{logic: logic, negate: false, base_filters: filters}}
    end
  end

  # Extract content between the first ( and the last ) in a well-formed expression.
  # e.g. "eq(name,value)" -> "name,value"
  # e.g. "and(eq(a,1),or(eq(b,2),eq(c,3)))" -> "eq(a,1),or(eq(b,2),eq(c,3))"
  defp extract_inner(str) do
    case :binary.match(str, "(") do
      {pos, 1} ->
        if String.ends_with?(str, ")") do
          {:ok, binary_part(str, pos + 1, byte_size(str) - pos - 2)}
        else
          Error.create(:filter, "unbalanced parentheses in `#{str}`")
        end

      :nomatch ->
        {:ok, str}
    end
  end

  # Split a string by commas at parenthesis depth 0, respecting nesting.
  # e.g. "eq(a,1),or(eq(b,2),eq(c,3))" -> ["eq(a,1)", "or(eq(b,2),eq(c,3))"]
  defp split_top_level(str) do
    str
    |> String.to_charlist()
    |> Enum.reduce({[], [], 0}, fn
      ?(, {parts, current, depth} -> {parts, [?( | current], depth + 1}
      ?), {parts, current, depth} -> {parts, [?) | current], depth - 1}
      ?,, {parts, current, 0} -> {[current |> Enum.reverse() |> List.to_string() | parts], [], 0}
      char, {parts, current, depth} -> {parts, [char | current], depth}
    end)
    |> then(fn {parts, current, _} ->
      [current |> Enum.reverse() |> List.to_string() | parts]
      |> Enum.reverse()
      |> Enum.reject(&(&1 == ""))
    end)
  end

  defp format_parameter_and_value(conn, data, :isnull) do
    get_condition(conn, data, :isnull, nil, false)
  end

  defp format_parameter_and_value(conn, data, operator) do
    case String.split(data, ",", parts: 2) do
      [parameter_id, value] ->
        get_condition(conn, parameter_id, operator, value, false)

      _ ->
        Error.create(:filter, "invalid value. Use `isnull()` operator to check null values")
    end
  end

  defp get_condition(conn, parameter_id, operator, value, negate) do
    project = conn.assigns[:arke_project]

    {parameter_id, path_ids} =
      parameter_id
      |> String.split(".")
      |> List.pop_at(-1)

    with {:ok, parameter} <- fetch_parameter(parameter_id, project),
         {:ok, path} <- get_path_parameters(path_ids, project) do
      {:ok,
       QueryManager.condition(parameter, operator, parse_value(value, operator), negate, path)}
    else
      {:error, msg} -> {:error, msg}
    end
  end

  defp get_path_parameters(path_ids, project) do
    Enum.reduce_while(path_ids, {:ok, []}, fn path_id, {:ok, acc} ->
      case fetch_parameter(path_id, project) do
        {:ok, parameter} -> {:cont, {:ok, [parameter | acc]}}
        {:error, msg} -> {:halt, {:error, msg}}
      end
    end)
    |> case do
      {:ok, path} -> {:ok, Enum.reverse(path)}
      error -> error
    end
  end

  defp fetch_parameter(parameter_id, project) do
    case Arke.Boundary.ParameterManager.get(parameter_id, project) do
      {:error, msg} -> {:error, msg}
      parameter -> {:ok, parameter}
    end
  end

  defp parse_value(val, :in) do
    # remove ( and ) from our string before split
    String.replace(val, ~r'[\(\])]', "")
    |> String.split(",")
  end

  defp parse_value(v, _operator), do: v

  defp get_operator("eq(" <> _rest), do: {:ok, :eq}
  defp get_operator("contains(" <> _rest), do: {:ok, :contains}
  defp get_operator("icontains(" <> _rest), do: {:ok, :icontains}
  defp get_operator("startswith(" <> _rest), do: {:ok, :startswith}
  defp get_operator("istartswith(" <> _rest), do: {:ok, :istartswith}
  defp get_operator("endswith(" <> _rest), do: {:ok, :endswith}
  defp get_operator("iendswith(" <> _rest), do: {:ok, :iendswith}
  defp get_operator("lte(" <> _rest), do: {:ok, :lte}
  defp get_operator("lt(" <> _rest), do: {:ok, :lt}
  defp get_operator("gt(" <> _rest), do: {:ok, :gt}
  defp get_operator("gte(" <> _rest), do: {:ok, :gte}
  defp get_operator("in(" <> _rest), do: {:ok, :in}
  defp get_operator("isnull(" <> _rest), do: {:ok, :isnull}

  defp get_operator(invalid_filter),
    do: Error.create(:filter, "filter `#{invalid_filter}` not available")
end
