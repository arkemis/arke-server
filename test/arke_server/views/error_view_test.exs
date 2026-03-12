defmodule ArkeServer.ErrorViewTest do
  use ArkeServer.ConnCase

  test "renders 404.json" do
    assert ArkeServer.ErrorView.render("404.json", []) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500.json" do
    assert ArkeServer.ErrorView.render("500.json", []) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
