defmodule HangukoWeb.PageController do
  use HangukoWeb, :controller

  # Logged-in users start from their study dashboard.
  def home(%{assigns: %{current_scope: %{user: %{}}}} = conn, _params) do
    redirect(conn, to: ~p"/dashboard")
  end

  def home(conn, _params) do
    render(conn, :home)
  end
end
