defmodule LocalizePad.Repo do
  use Ecto.Repo,
    otp_app: :localize_pad,
    adapter: Ecto.Adapters.Postgres
end
