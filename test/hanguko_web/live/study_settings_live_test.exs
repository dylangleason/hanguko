defmodule HangukoWeb.StudySettingsLiveTest do
  use HangukoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Hanguko.Accounts.Scope
  alias Hanguko.SRS

  setup :register_and_log_in_user

  test "validates and saves study settings", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/study/settings")

    html =
      view
      |> form("#study-settings-form", settings: %{daily_new_limit: "500", timezone: "Nowhere"})
      |> render_change()

    assert html =~ "must be less than or equal to 100"
    assert html =~ "is not a known time zone"

    view
    |> form("#study-settings-form",
      settings: %{daily_new_limit: "15", desired_retention: "0.85", timezone: "Asia/Seoul"}
    )
    |> render_submit()

    assert render(view) =~ "Study settings saved."

    assert %{daily_new_limit: 15, desired_retention: 0.85, timezone: "Asia/Seoul"} =
             SRS.get_settings(Scope.for_user(user))
  end
end
