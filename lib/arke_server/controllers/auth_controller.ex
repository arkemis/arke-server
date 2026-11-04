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

defmodule ArkeServer.AuthController do
  @moduledoc """
  Documentation for `ArkeServer.AuthController`. Used from the controller and via API not from CLI
  """

  use ArkeServer, :controller

  # Openapi request definition
  use ArkeServer.Openapi.Spec, module: ArkeServer.Openapi.AuthControllerSpec

  alias ArkeServer.ResponseManager
  alias ArkeAuth.Core.{User, Auth, Otp}
  alias Arke.Boundary.ArkeManager
  alias ArkeAuth.Boundary.OtpManager
  alias Arke.QueryManager
  alias Arke.Utils.ErrorGenerator, as: Error
  alias Arke.Utils.DatetimeHandler

  def mailer_module(), do: Application.get_env(:arke_server, :mailer_module)

  defp data_as_klist(data) do
    Enum.map(data, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  # App store reviewers sign in with a fixed code instead of a mailed OTP. The
  # path is enabled only when both APP_REVIEW_EMAIL and APP_REVIEW_CODE are
  # set: with no code configured, reviewer accounts get a real OTP.
  defp reviewer?(username) do
    not is_nil(get_review_code()) and username in get_review_email()
  end

  defp get_review_email() do
    case System.get_env("APP_REVIEW_EMAIL") do
      nil -> []
      data -> String.split(data, ",") |> Enum.map(&String.trim(&1)) |> Enum.reject(&(&1 == ""))
    end
  end

  defp get_review_code() do
    case System.get_env("APP_REVIEW_CODE") do
      nil -> nil
      "" -> nil
      code -> code
    end
  end

  @review_code_max_attempts 5
  @review_code_window 900

  # The review code never changes, so wrong guesses are throttled per username.
  defp check_review_code(username, otp) do
    key = {:app_review_code, username}

    cond do
      ArkeAuth.Boundary.AttemptLimiter.count(key) >= @review_code_max_attempts ->
        Error.create(:auth, "too many attempts")

      Plug.Crypto.secure_compare(to_string(otp), get_review_code()) ->
        :ok

      ArkeAuth.Boundary.AttemptLimiter.hit(key, @review_code_window) >=
          @review_code_max_attempts ->
        Error.create(:auth, "too many attempts")

      true ->
        Error.create(:auth, "invalid otp")
    end
  end

  @doc """
  Signin a user
  """
  def signup(%{body_params: params} = conn, %{"arke_id" => arke_id}) do
    project = get_project(conn.assigns[:arke_project])
    auth_mode = System.get_env("AUTH_MODE", "default")
    params = ArkeServer.Utils.MemberArke.drop_protected(params)

    # Only the member arkes in the self_signup group are open to sign-up;
    # any other arke, super_admin above all, is created by an admin.
    with true <- ArkeServer.Utils.MemberArke.self_signup?(arke_id, project),
         arke = ArkeManager.get(arke_id, project),
         %Arke.Core.Unit{} = unit <- Arke.Core.Unit.load(arke, data_as_klist(params), :create),
         {:ok, _unit} <- Arke.Validator.validate(unit, :create, project) do
      handle_signup_mode(conn, arke, params, project, auth_mode)
    else
      false -> send_error(conn, 403, Error.create(:auth, "signup not allowed"))
      {:error, errors} -> ResponseManager.send_resp(conn, 400, errors)
    end
  end

  defp handle_signup_mode(
         conn,
         arke,
         params,
         project,
         "default"
       ),
       do: handle_signup(conn, arke, params, project)

  defp handle_signup_mode(
         conn,
         _arke,
         %{
           "otp" => otp,
           "arke_system_user" => %{"username" => username},
           "email" => _email,
           "first_name" => _first_name,
           "last_name" => _last_name,
           "phone" => _phone,
           "channel" => channel
         } = params,
         project,
         "otp_mail"
       )
       when is_nil(otp) do
    case Otp.generate(project, username, "signup") do
      {:ok, otp} ->
        case channel do
          "mail" ->
            mailer_module().signup(conn, params, mode: "otp", unit: otp, code: otp.data.code)

          "sms" ->
            mailer_module().signup(conn, params, mode: "otp_sms", unit: otp, code: otp.data.code)
        end

        ResponseManager.send_resp(conn, 200, %{content: "OTP send successfully"})

      {:error, errors} ->
        ResponseManager.send_resp(conn, 401, nil, errors)
    end
  end

  defp handle_signup_mode(
         conn,
         arke,
         %{
           "otp" => otp,
           "arke_system_user" => %{"username" => username},
           "email" => _email,
           "first_name" => _first_name,
           "last_name" => _last_name
         } = params,
         project,
         "otp_mail"
       )
       when is_nil(otp),
       do:
         handle_signup_mode(
           conn,
           arke,
           Map.merge(params, %{"phone" => nil, "channel" => "mail"}),
           project,
           "otp_mail"
         )

  defp handle_signup_mode(
         conn,
         arke,
         %{"otp" => otp, "arke_system_user" => %{"username" => username}} = params,
         project,
         "otp_mail"
       ) do
    case OtpManager.verify_code(project, username, "signup", otp) do
      {:ok, _otp} -> handle_signup(conn, arke, params, project)
      error -> send_otp_error(conn, error)
    end
  end

  defp handle_signup_mode(conn, _, _, _project, "otp_mail"),
    do: params_required(conn, ["username", "password", "otp"])

  defp handle_signup_mode(conn, _, _, _project, _), do: auth_not_active(conn)

  defp handle_signup(conn, arke, req_params, project) do
    {_, params} = Map.pop(req_params, "otp")

    with {:ok, params, arke_system_user} <-
           check_user_on_signup(params, Map.get(params, "arke_system_user", nil)),
         params = Map.put(params, "last_access_time", NaiveDateTime.utc_now()),
         {:ok, _member} <- QueryManager.create(project, arke, data_as_klist(params)) do
      username = Map.get(arke_system_user, "username", nil)
      password = Map.get(arke_system_user, "password", nil)

      Auth.validate_credentials(username, password, project)
      |> case do
        {:ok, member, access_token, refresh_token} ->
          content =
            Map.merge(Arke.StructManager.encode(member, type: :json), %{
              access_token: access_token,
              refresh_token: refresh_token
            })

          mailer_module().signup(conn, params, member: member, response_body: content)
          ResponseManager.send_resp(conn, 200, %{content: content})

        {:error, error} ->
          ResponseManager.send_resp(conn, 401, nil, error)
      end
    else
      {:error, errors} -> ResponseManager.send_resp(conn, 400, errors)
    end
  end

  defp check_user_on_signup(_params, arke_system_user)
       when is_nil(arke_system_user) or arke_system_user == "" or arke_system_user == %{},
       do: {:error, "arke_system_user is required"}

  defp check_user_on_signup(params, arke_system_user) when is_binary(arke_system_user) do
    case Jason.decode(arke_system_user) do
      {:ok, u} ->
        params = Map.merge(params, %{"arke_system_user" => u})
        {:ok, params, u}

      {:error, _} ->
        {:error, "arke_system_user is not a valid json"}
    end
  end

  defp check_user_on_signup(params, arke_system_user), do: {:ok, params, arke_system_user}

  @doc """
  Signin a user
  """

  #### GET ######

  # TODO improve it in arke_auth
  def signin(conn, %{"token" => token} = params) do
    project = get_project(conn.assigns[:arke_project])

    case QueryManager.get_by(project: project, group: :arke_auth_member, auth_token: token) do
      nil ->
        ResponseManager.send_resp(conn, 401, "Unauthorized")

      member ->
        with {:ok, _resource, access_token, refresh_token} <-
               Auth.create_tokens(Auth.format_member(member)) do
          content =
            Map.merge(Arke.StructManager.encode(member, type: :json), %{
              access_token: access_token,
              refresh_token: refresh_token
            })

          update_member_access_time(member, auth_token: nil)
          ResponseManager.send_resp(conn, 200, %{content: content})
        else
          {:error, type} ->
            ResponseManager.send_resp(conn, 401, "Unauthorized")
        end
    end
  end

  def signin(conn, %{"auth_token" => auth_token} = params) do
    project = get_project(conn.assigns[:arke_project])

    case QueryManager.get_by(project: project, arke_id: :temporary_token, id: auth_token) do
      nil ->
        ResponseManager.send_resp(conn, 401, "Unauthorized")

      temporary_token ->
        case validate_temporary_token(temporary_token) do
          {:error, errors} ->
            ResponseManager.send_resp(conn, 401, errors)

          {:ok, _} ->
            case get_member(project, temporary_token) do
              {:error, errors} ->
                ResponseManager.send_resp(conn, 403, errors)

              {:ok, member} ->
                with {:ok, _resource, access_token, refresh_token} <-
                       Auth.create_tokens(Auth.format_member(member)) do
                  manage_reusability(project, temporary_token)

                  content =
                    Map.merge(Arke.StructManager.encode(member, type: :json), %{
                      access_token: access_token,
                      refresh_token: refresh_token
                    })

                  update_member_access_time(member)
                  ResponseManager.send_resp(conn, 200, %{content: content})
                else
                  {:error, type} ->
                    ResponseManager.send_resp(conn, 401, "Unauthorized")
                end
            end
        end
    end
  end

  defp manage_reusability(project, %{data: %{is_reusable: false}} = token),
    do: QueryManager.delete(project, token)

  defp manage_reusability(_project, _token), do: nil

  # A token is valid strictly before its expiry. arke_auth always sets one, so
  # a token without it is treated as expired.
  defp validate_temporary_token(%{data: %{expiration_datetime: %DateTime{} = expiry}} = token),
    do: check_expiry(token, DateTime.compare(expiry, DateTime.utc_now()))

  defp validate_temporary_token(
         %{data: %{expiration_datetime: %NaiveDateTime{} = expiry}} = token
       ),
       do: check_expiry(token, NaiveDateTime.compare(expiry, NaiveDateTime.utc_now()))

  defp validate_temporary_token(_token), do: Error.create(:auth, "token expired")

  defp check_expiry(token, :gt), do: {:ok, token}
  defp check_expiry(_token, _comparison), do: Error.create(:auth, "token expired")

  defp get_member(project, token) do
    case QueryManager.get_by(
           project: project,
           group: :arke_auth_member,
           id: token.data.link_member
         ) do
      member -> {:ok, member}
      _ -> Error.create(:auth, "member not found")
    end
  end

  #### POST ######
  def signin(conn, %{"username" => username, "password" => password} = params) do
    project = get_project(conn.assigns[:arke_project])
    auth_mode = System.get_env("AUTH_MODE", "default")

    Auth.validate_credentials(username, password, project)
    |> case do
      {:ok, _member, _access_token, _refresh_token} ->
        handle_signin_mode(conn, params, project, auth_mode)

      {:error, messages} ->
        ResponseManager.send_resp(conn, 401, messages)
    end
  end

  def signin(conn, _params), do: ResponseManager.send_resp(conn, 404, nil)

  defp handle_signin_mode(
         conn,
         %{"username" => username, "password" => password},
         project,
         "default"
       ),
       do: handle_signin(conn, username, password, project)

  defp handle_signin_mode(conn, _, _project, "default"),
    do: params_required(conn, ["username", "password"])

  defp handle_signin_mode(
         conn,
         %{"username" => username, "password" => password, "otp" => otp, "channel" => channel},
         project,
         "otp_mail"
       )
       when is_nil(otp) do
    Auth.validate_credentials(username, password, project)
    |> case do
      {:ok, member, _access_token, _refresh_token} ->
        data = %{
          arke_id: member.arke_id,
          id: member.id,
          arke_system_user: member.data.arke_system_user,
          email: Map.get(member.data, :email),
          phone: hide_phone_number(Map.get(member.data, :phone, nil)),
          inactive: Map.get(member.data, :inactive, false)
        }

        if reviewer?(username) do
          mailer_module().signin(conn, member, mode: "otp", code: get_review_code())
          ResponseManager.send_resp(conn, 200, data, "OTP send successfully")
        else
          case Otp.generate(project, member.id, "signin") do
            {:ok, otp} ->
              case channel do
                "mail" ->
                  mailer_module().signin(conn, member,
                    mode: "otp",
                    unit: otp,
                    code: otp.data.code
                  )

                "sms" ->
                  mailer_module().signin(conn, member,
                    mode: "otp_sms",
                    unit: otp,
                    code: otp.data.code
                  )
              end

              ResponseManager.send_resp(conn, 200, data, "OTP send successfully")

            {:error, errors} ->
              ResponseManager.send_resp(conn, 401, nil, errors)
          end
        end

      {:error, error} ->
        ResponseManager.send_resp(conn, 401, nil, error)
    end
  end

  defp handle_signin_mode(
         conn,
         %{"username" => username, "password" => password, "otp" => otp} = params,
         project,
         "otp_mail"
       )
       when is_nil(otp) do
    handle_signin_mode(conn, Map.merge(params, %{"channel" => "mail"}), project, "otp_mail")
  end

  defp handle_signin_mode(
         conn,
         %{"username" => username, "password" => password, "otp" => otp},
         project,
         "otp_mail"
       ) do
    Auth.validate_credentials(username, password, project)
    |> case do
      {:ok, member, _access_token, _refresh_token} ->
        if reviewer?(username) do
          case check_review_code(username, otp) do
            :ok -> handle_signin(conn, username, password, project)
            {:error, [%{message: "too many attempts"}]} = e -> send_error(conn, 429, e)
            {:error, _} -> ResponseManager.send_resp(conn, 401, nil, "Unauthorized")
          end
        else
          case OtpManager.verify_code(project, member, "signin", otp) do
            {:ok, _otp} -> handle_signin(conn, username, password, project)
            error -> send_otp_error(conn, error)
          end
        end

      {:error, error} ->
        ResponseManager.send_resp(conn, 401, nil, error)
    end
  end

  defp handle_signin_mode(conn, _, _project, "otp_mail"),
    do: params_required(conn, ["username", "password", "otp"])

  defp handle_signin_mode(conn, _, _project, _), do: auth_not_active(conn)

  defp handle_signin(conn, username, password, project) do
    Auth.validate_credentials(username, password, project)
    |> case do
      {:ok, member, access_token, refresh_token} ->
        content =
          Map.merge(Arke.StructManager.encode(member, type: :json), %{
            access_token: access_token,
            refresh_token: refresh_token
          })

        update_member_access_time(member)

        ResponseManager.send_resp(conn, 200, %{content: content})

      {:error, error} ->
        ResponseManager.send_resp(conn, 401, nil, error)
    end
  end

  def update_member_access_time(member, args \\ []) do
    datetime_now = NaiveDateTime.utc_now()
    update_data = [last_access_time: datetime_now]

    update_data =
      if Map.get(member.data, :first_access_time, nil) == nil,
        do: Keyword.put(update_data, :first_access_time, datetime_now),
        else: update_data

    update_data = Keyword.merge(update_data, args)
    QueryManager.update(member, update_data)
  end

  defp hide_phone_number(nil), do: nil
  defp hide_phone_number(""), do: nil

  defp hide_phone_number(phone_number) do
    masked_part = String.duplicate("*", String.length(phone_number) - 3)
    masked_part <> String.slice(phone_number, -3, 3)
  end

  @doc """
  Refresh the JWT tokens. Returns 200 and the tokes if ok
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    # The member comes from the refresh token itself; no access token is
    # needed (it may well have expired).
    Auth.refresh_tokens(refresh_token)
    |> case do
      {:ok, access_token, refresh_token} ->
        ResponseManager.send_resp(conn, 200, %{
          content: %{access_token: access_token, refresh_token: refresh_token}
        })

      {:error, error} ->
        ResponseManager.send_resp(conn, 400, nil, error)
    end
  end

  def refresh(conn, _params) do
    {:error, msg} = Error.create(:auth, "missing 'refresh_token' params")
    ResponseManager.send_resp(conn, 400, msg)
  end

  @doc """
  Verify if the token is still valid. Returns 200 if true
    - conn => %Plug.Conn{}
  """
  def verify(conn, _) do
    ResponseManager.send_resp(conn, 200, nil)
  end

  @doc """
  Change user password
  """

  def change_password(conn, %{"old_password" => _, "password" => _} = params) do
    auth_mode = System.get_env("AUTH_MODE", "default")
    member = ArkeAuth.Guardian.get_member(conn)
    handle_change_password_mode(conn, params, member, auth_mode)
  end

  def change_password(conn, _), do: ResponseManager.send_resp(conn, 400, nil)

  defp handle_change_password_mode(
         conn,
         %{"old_password" => old_pwd, "password" => new_pwd},
         member,
         _mode
       ),
       do: handle_change_password(conn, member, old_pwd, new_pwd)

  defp handle_change_password_mode(conn, _, _, _mode),
    do: params_required(conn, ["old_password", "password"])

  defp handle_change_password_mode(conn, _, _, _), do: auth_not_active(conn)

  defp handle_change_password(conn, member, old_pwd, new_pwd) do
    user =
      QueryManager.get_by(project: :arke_system, arke_id: :user, id: member.data.arke_system_user)

    Auth.change_password(user, old_pwd, new_pwd)
    |> case do
      {:ok, user} ->
        ResponseManager.send_resp(conn, 200, %{
          content: Arke.StructManager.encode(user, type: :json)
        })

      {:error, error} ->
        ResponseManager.send_resp(conn, 400, nil, error)
    end
  end

  @doc """
  Reset user password
  """

  @recover_password_sent "An email has been sent to the given email"

  def recover_password(conn, %{"email" => email} = params) do
    project = get_project(conn.assigns[:arke_project])
    auth_mode = System.get_env("AUTH_MODE", "default")

    member = QueryManager.get_by(project: project, group_id: :arke_auth_member, email: email)
    handle_recover_password_mode(conn, params, member, auth_mode)
  end

  def recover_password(conn, _), do: ResponseManager.send_resp(conn, 400, nil)

  # An unknown email gets the same answer as a known one, so the endpoint
  # does not tell who has an account.
  defp handle_recover_password_mode(conn, %{"email" => _}, nil, "default"),
    do: ResponseManager.send_resp(conn, 200, @recover_password_sent)

  defp handle_recover_password_mode(conn, %{"email" => _, "otp" => nil}, nil, "otp_mail"),
    do: ResponseManager.send_resp(conn, 200, %{content: "OTP send successfully"})

  defp handle_recover_password_mode(
         conn,
         %{"email" => email} = _params,
         _member,
         "default"
       ),
       do: handle_recover_password(conn, email, "default")

  defp handle_recover_password_mode(conn, _, _, "default"), do: params_required(conn, ["email"])

  defp handle_recover_password_mode(
         conn,
         %{"email" => _email, "otp" => otp, "channel" => channel},
         %{metadata: %{project: project}} = member,
         "otp_mail"
       )
       when is_nil(otp) do
    case Otp.generate(project, member.id, "reset_password") do
      {:ok, otp} ->
        case channel do
          "mail" ->
            mailer_module().reset_password(conn, member,
              mode: "otp",
              unit: otp,
              code: otp.data.code
            )

          "sms" ->
            mailer_module().reset_password(conn, member,
              mode: "otp_sms",
              unit: otp,
              code: otp.data.code
            )
        end

        ResponseManager.send_resp(conn, 200, %{content: "OTP send successfully"})

      {:error, errors} ->
        ResponseManager.send_resp(conn, 401, nil, errors)
    end
  end

  defp handle_recover_password_mode(
         conn,
         %{"email" => _email, "otp" => otp} = params,
         %{metadata: %{project: project}} = member,
         "otp_mail"
       )
       when is_nil(otp) do
    handle_recover_password_mode(
      conn,
      Map.merge(params, %{"channel" => "mail"}),
      member,
      "otp_mail"
    )
  end

  defp handle_recover_password_mode(conn, _, _, "otp_mail"),
    do: params_required(conn, ["email", "otp"])

  defp handle_recover_password_mode(conn, _, _, _), do: auth_not_active(conn)

  defp handle_recover_password(conn, email, "default") do
    default_msg = @recover_password_sent

    case QueryManager.get_by(email: email, arke_id: :user, project: :arke_system) do
      nil ->
        ResponseManager.send_resp(conn, 200, default_msg)

      user ->
        old_token_list =
          QueryManager.filter_by(
            project: :arke_system,
            arke_id: :reset_password_token,
            user_id: user.id
          )

        Enum.each(old_token_list, fn unit -> QueryManager.delete(:arke_system, unit) end)
        token_model = ArkeManager.get(:reset_password_token, :arke_system)

        case QueryManager.create(:arke_system, token_model, %{user_id: to_string(user.id)}) do
          {:error, _error} ->
            ResponseManager.send_resp(conn, 200, default_msg)

          {:ok, unit} ->
            url_token = unit.data.token
            endpoint = "#{System.get_env("RESET_PASSWORD_ENDPOINT", "")}/#{url_token}"

            mailer_module().reset_password(conn, user,
              mode: "email",
              unit: unit,
              endpoint: endpoint
            )

            ResponseManager.send_resp(conn, 200, default_msg)
        end
    end
  end

  def reset_password(conn, params) do
    project = get_project(conn.assigns[:arke_project])
    auth_mode = System.get_env("AUTH_MODE", "default")

    email = Map.get(params, "email", nil)

    member = QueryManager.get_by(project: project, group_id: :arke_auth_member, email: email)
    handle_reset_password_mode(conn, params, member, auth_mode)
  end

  defp handle_reset_password_mode(
         conn,
         %{"new_password" => new_password, "token" => token} = _params,
         _member,
         "default"
       ) do
    with %Arke.Core.Unit{} = token_unit <-
           QueryManager.get_by(
             arke_id: :reset_password_token,
             token: token,
             project: :arke_system
           ),
         {:ok, token_unit} <- check_token_expiration(token_unit),
         %Arke.Core.Unit{} = user <-
           QueryManager.get_by(id: token_unit.data.user_id, project: :arke_system),
         {:ok, _updated_user} <- User.update_password(user, new_password) do
      QueryManager.delete(:arke_system, token_unit)
      ResponseManager.send_resp(conn, 200, nil)
    else
      nil ->
        ResponseManager.send_resp(conn, 400, nil, %{
          context: :auth,
          message: "invalid token"
        })

      {:error, msg} ->
        ResponseManager.send_resp(conn, 400, nil, msg)
    end
  end

  defp handle_reset_password_mode(
         conn,
         %{"new_password" => new_password, "otp" => otp},
         %{metadata: %{project: project}} = member,
         "otp_mail"
       ) do
    with {:ok, _otp} <- OtpManager.verify_code(project, member, "reset_password", otp) do
      user =
        QueryManager.get_by(
          id: member.data.arke_system_user,
          arke_id: :user,
          project: :arke_system
        )

      case User.update_password(user, new_password) do
        {:ok, _} -> ResponseManager.send_resp(conn, 200, nil, nil)
        {:error, msg} -> ResponseManager.send_resp(conn, 400, nil, msg)
      end
    else
      error -> send_otp_error(conn, error)
    end
  end

  # No member carries the email: answer as for a wrong code.
  defp handle_reset_password_mode(conn, %{"new_password" => _, "otp" => _}, nil, "otp_mail"),
    do: send_otp_error(conn, Error.create(:auth, "invalid otp"))

  defp handle_reset_password_mode(conn, _, _, "default"),
    do: params_required(conn, ["token", "new_password"])

  defp handle_reset_password_mode(conn, _, _, "otp_mail"),
    do: params_required(conn, ["email", "otp", "new_password"])

  defp handle_reset_password_mode(conn, _, _, _), do: auth_not_active(conn)

  defp get_project(project) when is_nil(project), do: :arke_system
  defp get_project(project), do: project

  defp check_token_expiration(%Arke.Core.Unit{} = token) do
    with {:ok, value} <- DatetimeHandler.parse_datetime(token.data.expiration),
         true <- DatetimeHandler.after?(value, DatetimeHandler.now(:datetime)) do
      {:ok, token}
    else
      _ -> Error.create(:auth, "expired token")
    end
  end

  defp check_token_expiration(_token), do: Error.create(:auth, "invalid token")

  defp send_otp_error(conn, {:error, [%{message: "otp expired"}]} = error),
    do: send_error(conn, 410, error)

  defp send_otp_error(conn, {:error, [%{message: "too many attempts"}]} = error),
    do: send_error(conn, 429, error)

  defp send_otp_error(conn, error), do: send_error(conn, 401, error)

  defp send_error(conn, status, {:error, msg}),
    do: ResponseManager.send_resp(conn, status, nil, msg)

  defp auth_not_active(conn) do
    {:error, msg} = Error.create(:auth, "auth method not active")
    ResponseManager.send_resp(conn, 400, msg)
  end

  defp params_required(conn, param) do
    param_msg = Enum.map(param, fn p -> "#{String.downcase(p)}" end) |> Enum.join(", ")
    {:error, msg} = Error.create(:auth, "#{param_msg} required")
    ResponseManager.send_resp(conn, 400, msg)
  end
end
