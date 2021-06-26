defmodule DjRumble.Chats.MessageTest do
  @moduledoc """
  Round tests
  """
  use DjRumble.DataCase
  use DjRumble.Support.Chats.MessageCase
  use ExUnit.Case

  import DjRumble.AccountsFixtures

  describe "round" do
    alias DjRumble.Chats.Message

    @default_timezone "America/Buenos_Aires"

    test "create_message/2 returns a %Message{}" do
      message = "Hello!"
      user = user_fixture()

      %Message{user: ^user, message: ^message} =
        create_message([message, user, @default_timezone])
    end
  end
end
