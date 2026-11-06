defmodule ArkeServer.ArkeDevFunctionController do
  use ArkeServer, :controller
  alias ArkeServer.ResponseManager

  # The project is the one in the arke-project-key header, which the token
  # has been checked against.
  def export_arke_db_stucture(conn, _params) do
    project = conn.assigns[:arke_project]
    member = ArkeAuth.Guardian.get_member(conn)

    case member.arke_id do
      :super_admin ->
        ResponseManager.send_resp(
          conn,
          200,
          Arke.Utils.Export.get_db_structure(project, all: true)
        )

      _ ->
        ResponseManager.send_resp(conn, 401, nil)
    end
  end
end
