defmodule ArkeServer.Utils.QueryFiltersTest do
  use ExUnit.Case, async: true

  alias ArkeServer.Utils.QueryFilters
  alias Arke.Core.Query.{Filter, BaseFilter}

  # Fake conn — get_from_string only reads conn.assigns[:arke_project]
  @conn %{assigns: %{arke_project: :arke_system}}

  # ------------------------------------------------------------------
  # Flat filters (existing behaviour — regression guard)
  # ------------------------------------------------------------------

  describe "flat filters" do
    test "and with single eq" do
      assert {:ok, {:and, false, [%BaseFilter{operator: :eq, value: "hello"}]}} =
               QueryFilters.get_from_string(@conn, "and(eq(string_support,hello))")
    end

    test "and with two conditions" do
      {:ok, {:and, false, filters}} =
        QueryFilters.get_from_string(@conn, "and(eq(string_support,hello),gt(integer_support,5))")

      assert length(filters) == 2
      assert Enum.all?(filters, &match?(%BaseFilter{}, &1))

      ops = Enum.map(filters, & &1.operator) |> Enum.sort()
      assert ops == [:eq, :gt]
    end

    test "or with two conditions" do
      {:ok, {:or, false, filters}} =
        QueryFilters.get_from_string(@conn, "or(eq(string_support,a),eq(string_support,b))")

      assert length(filters) == 2
      assert Enum.all?(filters, &match?(%BaseFilter{operator: :eq}, &1))
    end

    test "not wrapping a single condition" do
      {:ok, {:and, false, [%BaseFilter{operator: :eq, negate: true}]}} =
        QueryFilters.get_from_string(@conn, "not(eq(string_support,hello))")
    end

    test "nil input returns ok nil" do
      assert {:ok, nil} = QueryFilters.get_from_string(@conn, nil)
    end

    test "isnull operator" do
      {:ok, {:and, false, [%BaseFilter{operator: :isnull}]}} =
        QueryFilters.get_from_string(@conn, "and(isnull(string_support))")
    end

    test "in operator with list value" do
      {:ok, {:and, false, [%BaseFilter{operator: :in, value: values}]}} =
        QueryFilters.get_from_string(@conn, "and(in(integer_support,(3,10)))")

      assert values == ["3", "10"]
    end
  end

  # ------------------------------------------------------------------
  # Nested filters (new behaviour)
  # ------------------------------------------------------------------

  describe "nested filters" do
    test "or inside and produces Filter struct as child" do
      {:ok, {:and, false, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "and(or(eq(string_support,a),eq(string_support,b)),eq(integer_support,5))"
        )

      assert length(filters) == 2

      # One child should be a nested Filter (the or group), one a BaseFilter
      {nested, base} = Enum.split_with(filters, &match?(%Filter{}, &1))
      assert length(nested) == 1
      assert length(base) == 1

      [%Filter{logic: :or, negate: false, base_filters: or_children}] = nested
      assert length(or_children) == 2
      assert Enum.all?(or_children, &match?(%BaseFilter{operator: :eq}, &1))

      [%BaseFilter{operator: :eq, value: "5"}] = base
    end

    test "and inside or" do
      {:ok, {:or, false, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "or(and(eq(string_support,a),gt(integer_support,10)),eq(string_support,b))"
        )

      assert length(filters) == 2

      {nested, base} = Enum.split_with(filters, &match?(%Filter{}, &1))
      assert length(nested) == 1
      assert length(base) == 1

      [%Filter{logic: :and, negate: false, base_filters: and_children}] = nested
      assert length(and_children) == 2
      ops = Enum.map(and_children, & &1.operator) |> Enum.sort()
      assert ops == [:eq, :gt]
    end

    test "multiple nested groups inside and" do
      {:ok, {:and, false, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "and(or(eq(string_support,a),eq(string_support,b)),or(gt(integer_support,5),lt(float_support,7.0)))"
        )

      assert length(filters) == 2
      assert Enum.all?(filters, &match?(%Filter{logic: :or}, &1))

      [first_or, second_or] = filters
      assert length(first_or.base_filters) == 2
      assert length(second_or.base_filters) == 2
    end

    test "three levels deep: or(and(eq,or(gt,lt)),eq)" do
      {:ok, {:or, false, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "or(and(eq(string_support,a),or(gt(integer_support,3),lt(float_support,1.0))),eq(string_support,b))"
        )

      assert length(filters) == 2

      {nested, base} = Enum.split_with(filters, &match?(%Filter{}, &1))
      assert length(nested) == 1
      assert length(base) == 1

      # The and() group
      [%Filter{logic: :and, base_filters: and_children}] = nested
      assert length(and_children) == 2

      {inner_nested, inner_base} = Enum.split_with(and_children, &match?(%Filter{}, &1))
      assert length(inner_nested) == 1
      assert length(inner_base) == 1

      # The inner or() group
      [%Filter{logic: :or, base_filters: inner_or_children}] = inner_nested
      assert length(inner_or_children) == 2
      inner_ops = Enum.map(inner_or_children, & &1.operator) |> Enum.sort()
      assert inner_ops == [:gt, :lt]
    end
  end

  # ------------------------------------------------------------------
  # not() with nesting
  # ------------------------------------------------------------------

  describe "not with nesting" do
    test "not wrapping an or group sets negate on the Filter" do
      {:ok, {:and, false, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "and(not(or(eq(string_support,a),eq(string_support,b))),eq(integer_support,12))"
        )

      assert length(filters) == 2

      {nested, _base} = Enum.split_with(filters, &match?(%Filter{}, &1))
      [%Filter{logic: :or, negate: true, base_filters: children}] = nested
      assert length(children) == 2
      # The inner BaseFilters themselves should NOT be negated
      assert Enum.all?(children, &(&1.negate == false))
    end

    test "not wrapping an and group" do
      {:ok, {:or, false, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "or(not(and(eq(string_support,a),eq(integer_support,5))),eq(float_support,2.5))"
        )

      {nested, _base} = Enum.split_with(filters, &match?(%Filter{}, &1))
      [%Filter{logic: :and, negate: true}] = nested
    end

    test "top-level not(and(...)) sets negate on the tuple" do
      {:ok, {:and, true, filters}} =
        QueryFilters.get_from_string(
          @conn,
          "not(and(eq(string_support,a),eq(integer_support,5)))"
        )

      assert length(filters) == 2
      assert Enum.all?(filters, &match?(%BaseFilter{negate: false}, &1))
    end
  end

  # ------------------------------------------------------------------
  # Error handling
  # ------------------------------------------------------------------

  describe "error handling" do
    test "invalid operator returns error" do
      assert {:error, _} = QueryFilters.get_from_string(@conn, "and(bad(string_support,a))")
    end

    test "invalid parameter returns error" do
      assert {:error, _} =
               QueryFilters.get_from_string(@conn, "and(eq(nonexistent_param,value))")
    end
  end
end
