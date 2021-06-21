defmodule DjRumble.Round.RoundServerTest do
  @moduledoc """
  Rounds servers tests
  """
  use DjRumble.DataCase
  use ExUnit.Case

  import DjRumble.AccountsFixtures
  import DjRumble.RoomsFixtures

  alias DjRumble.Rounds.{Log, Round, RoundServer}

  alias DjRumbleWeb.Channels

  describe "round_server client interface" do
    setup do
      room = room_fixture()
      round_genserver_pid = start_supervised!({RoundServer, {room.slug}})
      %{room: room, pid: round_genserver_pid}
    end

    defp tick(pid, times) do
      for _ <- 1..times do
        :ok = Process.send(pid, :tick, [])
      end
    end

    test "start_link/1 starts a round server", %{pid: pid} do
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "get_room_slug/1 returns a room slug", %{pid: pid, room: room} do
      assert RoundServer.get_room_slug(pid) == room.slug
    end

    test "start_round/1 returns :ok", %{pid: pid} do
      assert RoundServer.start_round(pid) == :ok
    end

    test "start_round/1 ticks until the round pid terminates", %{pid: pid} do
      :ok = RoundServer.start_round(pid)
      assert Process.alive?(pid)
    end

    test "get_round/1 returns a scheduled round", %{pid: pid} do
      %Round.Scheduled{time: 0, elapsed_time: elapsed_time, score: score} =
        RoundServer.get_round(pid)

      assert elapsed_time == 0
      assert score == {0, 0}
    end

    test "get_round/1 returns a round that is in progress", %{pid: pid} do
      :ok = RoundServer.start_round(pid)

      %Round.InProgress{time: 0, elapsed_time: elapsed_time, score: score, log: log} =
        RoundServer.get_round(pid)

      assert elapsed_time == 0
      assert score == {0, 0}
      assert log == Log.new()
    end

    test "get_narration/1 returns a log from a round that is in progress", %{pid: pid} do
      :ok = RoundServer.start_round(pid)
      assert RoundServer.get_narration(pid) == Round.narrate(Round.InProgress.new())
    end

    test "set_round_time/2 returns :ok", %{pid: pid} do
      time = 10
      :ok = RoundServer.set_round_time(pid, time)
      %Round.Scheduled{time: ^time} = RoundServer.get_round(pid)
    end

    test "score/2 returns a round with a positive score", %{pid: pid} do
      # Setup
      :ok = RoundServer.start_round(pid)
      user = user_fixture()

      # Exercise
      round = RoundServer.score(pid, user, :positive)

      # Verify
      %Round.InProgress{score: {1, 0}} = round
    end

    test "score/2 returns a round with a negative score", %{pid: pid} do
      # Setup
      :ok = RoundServer.start_round(pid)
      user = user_fixture()

      # Exercise
      round = RoundServer.score(pid, user, :negative)

      # Verify
      %Round.InProgress{score: {0, 1}} = round
    end

    test "handle_info/2 :tick updates a round that is in progress", %{pid: pid} do
      :ok = RoundServer.start_round(pid)
      ticks = length(tick(pid, 1))
      log = Log.new()
      %Round.InProgress{time: 0, elapsed_time: ^ticks, log: ^log} = RoundServer.get_round(pid)
    end

    test "handle_info/2 :tick updates many times a round that is in progress", %{pid: pid} do
      :ok = RoundServer.start_round(pid)
      ticks = length(tick(pid, 10))
      log = Log.new()
      %Round.InProgress{time: 0, elapsed_time: ^ticks, log: ^log} = RoundServer.get_round(pid)
    end

    test "handle_info/2 :tick updates many times a round that is in progress until it finishes",
         %{pid: pid} do
      # Setup
      :ok = RoundServer.set_round_time(pid, 10)
      :ok = RoundServer.start_round(pid)

      # Exercise
      _ticks = tick(pid, 10)

      # Verify
      # We sleep for a few miliseconds to wait for the server to shutdown the
      # round properly
      :ok = Process.sleep(30)
      refute Process.alive?(pid)
    end
  end

  describe "round_server server implementation" do
    setup do
      room = room_fixture(%{}, %{preload: true})

      state = RoundServer.initial_state(%{room_slug: room.slug, round: Round.schedule(0)})

      %{room: room, state: state}
    end

    defp user_fixtures(n) do
      for _n <- 1..n, do: user_fixture()
    end

    defp handle_start_round(state) do
      response = RoundServer.handle_call(:start_round, nil, state)

      {:reply, :ok, %{round: %Round.InProgress{}} = state} = response

      state
    end

    defp handle_get_round(state, callbacks) do
      response = RoundServer.handle_call(:get_round, nil, state)

      {:reply, round, state} = response

      Enum.each(callbacks, & &1.(round))

      state
    end

    defp handle_get_narration(state, callbacks) do
      response = RoundServer.handle_call(:get_narration, nil, state)

      {:reply, log, state} = response

      Enum.each(callbacks, & &1.(log))

      state
    end

    defp handle_tick(state, callback) do
      response = RoundServer.handle_info(:tick, state)

      callback.(response)
    end

    defp handle_set_round_time(state, time) do
      response = RoundServer.handle_call({:set_round_time, time}, nil, state)

      {:reply, :ok, state} = response

      state
    end

    defp handle_score(state, user, type) do
      response = RoundServer.handle_call({:score, user, type}, nil, state)

      {:reply, new_round, %{round: round} = state} = response

      assert new_round == round

      state
    end

    defp handle_scores(state, users_scores) do
      Enum.reduce(users_scores, {[], state}, fn {user, score}, {scores, state} ->
        {scores ++ [score], handle_score(state, user, score)}
      end)
    end

    defp generate_score(:mixed, users) do
      types = [:positive, :negative]

      Enum.map(users, fn user ->
        {user, Enum.at(types, Enum.random(0..(length(types) - 1)))}
      end)
    end

    defp generate_score(type, users) do
      Enum.map(users, fn user -> {user, type} end)
    end

    defp get_evaluated_score(scores, initial_score) do
      Enum.reduce(scores, initial_score, fn score, {p, n} ->
        case score do
          :positive -> {p + 1, n}
          :negative -> {p, n + 1}
        end
      end)
    end

    defp get_round(%{round: round}) do
      round
    end

    test "handle_call/3 :: :start_round is called and replies :ok", %{state: state} do
      _state = handle_start_round(state)

      Process.sleep(:timer.seconds(1))

      assert_received(:tick)
    end

    test "handle_call/3 :: :get_room_slug is called and replies with a room slug", %{
      room: room,
      state: state
    } do
      %{slug: slug} = room

      response = RoundServer.handle_call(:get_room_slug, nil, state)

      {:reply, ^slug, _state} = response
    end

    test "handle_call/3 :: :get_round is called and replies with a scheduled round", %{
      state: state
    } do
      _state =
        handle_get_round(state, [
          &assert(&1 == get_round(state))
        ])
    end

    test "handle_call/3 :: :get_round is called and replies with a round that is in progress", %{
      state: state
    } do
      state = handle_start_round(state)

      Process.sleep(:timer.seconds(1))

      _state =
        handle_get_round(state, [
          &assert(&1 == get_round(state))
        ])
    end

    test "handle_call/3 :: :get_narration is called and replies with a log from a round that is in progress",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()
        |> handle_tick(fn response ->
          {:noreply, %{room_slug: ^slug, round: %Round.InProgress{}} = state} = response
          state
        end)

      log = Log.new()
      round = %Round.InProgress{get_round(state) | log: log}

      # Exercise
      _state =
        handle_get_narration(state, [
          # Verify
          &assert(Round.narrate(round) == &1)
        ])
    end

    test "handle_call/3 :: :get_narration is called and replies with a log from a round that is finished",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()
        |> handle_tick(fn response ->
          {:noreply, %{room_slug: ^slug, round: %Round.InProgress{}} = state} = response
          state
        end)
        |> handle_tick(fn response ->
          {:stop, {:shutdown, %Round.Finished{}},
           %{room_slug: ^slug, round: %Round.Finished{}} = state} = response

          state
        end)

      log = Log.new()

      round = %Round.Finished{get_round(state) | log: log}

      # Exercise
      _state =
        handle_get_narration(state, [
          # Verify
          &assert(Round.narrate(round) == &1)
        ])
    end

    test "handle_call/3 :: {:set_round_time, non_neg_integer()} is called and replies :ok", %{
      room: room,
      state: state
    } do
      %{slug: slug} = room
      time = 140

      %{room_slug: ^slug, round: %Round.Scheduled{time: ^time}} =
        handle_set_round_time(state, time)
    end

    test "handle_call/3 :: {:score, %User{}, :positive} is called once and replies with a round with a positive score",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()

      %{room_slug: ^slug, round: %Round.InProgress{score: initial_score}} = state
      users = user_fixtures(1)
      users_scores = generate_score(:positive, users)
      scores = Enum.map(users_scores, fn {_user, score} -> score end)
      evaluated_score = get_evaluated_score(scores, initial_score)

      # Exercise
      {^scores, state} = handle_scores(state, users_scores)

      # Verify
      %{room_slug: ^slug, round: %Round.InProgress{score: ^evaluated_score}} = state
    end

    test "handle_call/3 :: {:score, %User{}, :positive} is called many times and replies with a round with a positive score",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()

      %{room_slug: ^slug, round: %Round.InProgress{score: initial_score}} = state
      users = user_fixtures(3)
      users_scores = generate_score(:positive, users)
      scores = Enum.map(users_scores, fn {_user, score} -> score end)
      evaluated_score = get_evaluated_score(scores, initial_score)

      # Exercise
      {^scores, state} = handle_scores(state, users_scores)

      # Verify
      %{room_slug: ^slug, round: %Round.InProgress{score: ^evaluated_score}} = state
    end

    test "handle_call/3 :: {:score, %User{}, :negative} is called once and replies with a round with a negative score",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()

      %{room_slug: ^slug, round: %Round.InProgress{score: initial_score}} = state
      users = user_fixtures(1)
      users_scores = generate_score(:negative, users)
      scores = Enum.map(users_scores, fn {_user, score} -> score end)
      evaluated_score = get_evaluated_score(scores, initial_score)

      # Exercise
      {^scores, state} = handle_scores(state, users_scores)

      # Verify
      %{room_slug: ^slug, round: %Round.InProgress{score: ^evaluated_score}} = state
    end

    test "handle_call/3 :: {:score, %User{}, :negative} is called many times and replies with a round with a negative score",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()

      %{room_slug: ^slug, round: %Round.InProgress{score: initial_score}} = state
      users = user_fixtures(3)
      users_scores = generate_score(:negative, users)
      scores = Enum.map(users_scores, fn {_user, score} -> score end)
      evaluated_score = get_evaluated_score(scores, initial_score)

      # Exercise
      {^scores, state} = handle_scores(state, users_scores)

      # Verify
      %{room_slug: ^slug, round: %Round.InProgress{score: ^evaluated_score}} = state
    end

    test "handle_call/3 :: {:score, %User{}, type} is called many times with mixed scores replies with a round with a score",
         %{room: room, state: state} do
      # Setup
      %{slug: slug} = room

      state =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()

      %{room_slug: ^slug, round: %Round.InProgress{score: initial_score}} = state
      users = user_fixtures(10)
      users_scores = generate_score(:mixed, users)
      scores = Enum.map(users_scores, fn {_user, score} -> score end)
      evaluated_score = get_evaluated_score(scores, initial_score)

      # Exercise
      {^scores, state} = handle_scores(state, users_scores)

      # Verify
      %{room_slug: ^slug, round: %Round.InProgress{score: ^evaluated_score}} = state
    end

    test "handle_info/2 :: :tick is called with a round that is in progress and does not reply",
         %{room: room, state: state} do
      %{slug: slug} = room

      :ok =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()
        |> handle_tick(fn response ->
          {:noreply, %{room_slug: ^slug, round: %Round.InProgress{}}} = response
          :ok
        end)
    end

    test "handle_info/2 :: :tick is called with a round that is in progress, sends a broadcast message and and does not reply",
         %{room: room, state: state} do
      %{slug: slug} = room

      :ok = Channels.subscribe(:room, slug)

      [user] = user_fixtures(1)

      :ok =
        state
        |> handle_set_round_time(2)
        |> handle_start_round()
        |> handle_score(user, :negative)
        |> handle_tick(fn response ->
          {:noreply, %{room_slug: ^slug, round: %Round.InProgress{}}} = response
          :ok
        end)

      assert_receive {:outcome_changed, %{round: %Round.InProgress{outcome: :thrown}}}
    end

    test "handle_info/2 :: :tick is called with a round that is in finished and stops", %{
      room: room,
      state: state
    } do
      %{slug: slug} = room

      :ok =
        state
        |> handle_set_round_time(1)
        |> handle_start_round()
        |> handle_tick(fn response ->
          {:stop, {:shutdown, %Round.Finished{}}, %{room_slug: ^slug, round: %Round.Finished{}}} =
            response

          :ok
        end)
    end
  end
end
