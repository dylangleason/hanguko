defmodule Hanguko.SRS.Settings do
  @moduledoc """
  A user's study preferences. Users without a saved row get the defaults.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "study_settings" do
    field :daily_new_limit, :integer, default: 10
    field :daily_review_limit, :integer, default: 200
    field :desired_retention, :float, default: 0.9
    field :timezone, :string
    field :day_rollover_hour, :integer, default: 4
    field :show_romanization, :boolean, default: true
    field :tts_rate, :float, default: 0.9
    # Recall cards ask for the Korean to be typed before the answer is shown.
    field :typed_answers, :boolean, default: false

    belongs_to :user, Hanguko.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :daily_new_limit,
      :daily_review_limit,
      :desired_retention,
      :timezone,
      :day_rollover_hour,
      :show_romanization,
      :tts_rate,
      :typed_answers
    ])
    |> validate_required([
      :daily_new_limit,
      :daily_review_limit,
      :desired_retention,
      :day_rollover_hour,
      :show_romanization,
      :tts_rate,
      :typed_answers
    ])
    |> validate_number(:daily_new_limit, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:daily_review_limit,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 9999
    )
    |> validate_number(:desired_retention,
      greater_than_or_equal_to: 0.7,
      less_than_or_equal_to: 0.97
    )
    |> validate_number(:day_rollover_hour, greater_than_or_equal_to: 0, less_than_or_equal_to: 23)
    |> validate_number(:tts_rate, greater_than_or_equal_to: 0.5, less_than_or_equal_to: 1.5)
    |> validate_change(:timezone, fn :timezone, timezone ->
      if valid_timezone?(timezone), do: [], else: [timezone: "is not a known time zone"]
    end)
    |> unique_constraint(:user_id)
  end

  @doc "Returns true if `timezone` is an IANA time zone name, e.g. `\"Asia/Seoul\"`."
  def valid_timezone?(timezone) when is_binary(timezone) do
    match?({:ok, _}, DateTime.now(timezone))
  end

  def valid_timezone?(_), do: false

  @doc "The time zone used to decide when a study day starts."
  def timezone(%__MODULE__{timezone: nil}), do: "Etc/UTC"
  def timezone(%__MODULE__{timezone: timezone}), do: timezone
end
