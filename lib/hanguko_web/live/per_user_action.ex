defmodule HangukoWeb.Live.PerUserAction do
  @moduledoc """
  Support for the per-user actions that public pages offer — enrolling in a
  deck, marking a grammar point learned. Those pages send anonymous visitors
  to the log-in page rather than failing (see "Web layer" in
  `guides/architecture.md`); this module gives that redirect, and the deck
  enrol/unenrol toggle that rides along with it, one definition instead of
  one per page.
  """

  use HangukoWeb, :verified_routes

  import Phoenix.LiveView, only: [push_navigate: 2]

  alias Hanguko.SRS

  @doc """
  Sends an anonymous visitor to the log-in page. Call this from the
  `handle_event` clause matched on `current_scope: nil`.
  """
  def require_scope(socket) do
    {:noreply, push_navigate(socket, to: ~p"/users/log-in")}
  end

  @doc """
  Enrols or unenrols `deck` for `scope`, undoing whatever `enrolled?` says
  the current state is, and returns the new state. Callers keep their own
  representation of it — a `MapSet` of enrolled ids, or a single boolean —
  and store the result however that page does.
  """
  def toggle_enroll(scope, deck, enrolled?) do
    if enrolled? do
      {:ok, _} = SRS.unenroll_deck(scope, deck)
      false
    else
      {:ok, _} = SRS.enroll_deck(scope, deck)
      true
    end
  end
end
