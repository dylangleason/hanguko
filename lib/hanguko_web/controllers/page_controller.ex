defmodule HangukoWeb.PageController do
  use HangukoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
