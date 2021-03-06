defmodule Doro.CLI do
  @moduledoc """
  Main entry point for incoming player commands.

  When a command comes in, it is parsed and then flows through like:
    1. Look for local entities (in room or inventory) named (ctx.object_id).
       If there is nothing named that we implicitly use the player.
    2. Transform the entities into a list of {<entity>, <behavior>}, where <behavior> is the behavior that
       can respond to `ctx.verb` in the current context.  For example, a `Portable` item that isn't
       in the player's inventory can't be dropped, even though the `Portable` behavior responds to
       the verb `drop`.
    3. Filter out non-responding entities from the list.
    4. If there is more than one after filtering, disambiguate.
       If there is only one, execute that behavior.
       If there are zero, output an error message.
  """

  import Doro.Comms
  alias Doro.Context
  alias Doro.Entity

  def interpret(player_id, s) do
    {verb, object_id} = Doro.Parser.parse(s)
    {:ok, ctx} = Doro.Context.create(s, player_id, verb, object_id)
    process_command(ctx)
  end

  # reflexive (player) command
  def process_command(ctx = %{object: nil, player: player}) do
    execute_possible_behaviors([{player, Doro.Entity.first_responder(player, ctx)}], ctx)
  end

  # transitive command
  def process_command(ctx = %{player: player, object_id: object_name}) do
    Doro.World.get_named_entities_in_locations(object_name, [player.id, player.props.location])
    |> Enum.map(fn entity -> {entity, Doro.Entity.first_responder(entity, ctx)} end)
    |> execute_possible_behaviors(ctx)
  end

  defp execute_possible_behaviors(entity_behaviors, ctx) do
    entity_behaviors
    |> Enum.filter(fn {_, behavior} -> behavior end)
    |> execute_entity_behavior(ctx)
  end

  defp execute_entity_behavior([], %Context{player: player}) do
    send_to_player(player, "Huh?")
  end

  defp execute_entity_behavior([{object, behavior}], ctx) do
    Doro.Behavior.execute(behavior, %{ctx | object: object})
  end

  defp execute_entity_behavior(entity_behaviors, %Context{player: player}) do
    entity_names =
      entity_behaviors
      |> Enum.map(fn {e, _} -> Entity.name(e) end)
      |> Enum.join(", ")

    send_to_player(player, "Which do you mean? #{entity_names}")
  end
end
