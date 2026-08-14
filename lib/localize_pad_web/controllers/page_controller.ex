defmodule LocalizePadWeb.PageController do
  use LocalizePadWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
