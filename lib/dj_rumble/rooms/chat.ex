defmodule DjRumble.Rooms.Chat do
  @moduledoc """
  Responsible for chat management
  """
  use Phoenix.HTML

  alias DjRumble.Accounts.User
  alias DjRumbleWeb.Presence

  def create_message(:chat_message, %{
        message: message,
        user: %User{username: username},
        timezone: timezone
      }) do
    {:chat_message,
     %{
       text: message,
       timestamp: create_timestamp(timezone),
       username: username
     }}
  end

  def create_message(:track_notification, %{video: video, timezone: timezone}) do
    %{title: title, added_by: %{user_id: _user_id}} = video

    username = "Juancito"
    #   case user_id do
    #     nil -> "visitor"
    #     user_id -> DjRumble.Accounts.get_user!(user_id).username
    #   end

    {:track_notification,
     %{
       added_by: username,
       video_title: title,
       timestamp: create_timestamp(timezone),
       username: "info"
     }}
  end

  def start_typing(slug, uuid) do
    topic = "room:" <> slug
    key = uuid
    payload = %{typing: true}
    update_presence_state(topic, key, payload)
  end

  def stop_typing(slug, uuid) do
    topic = "room:" <> slug
    key = uuid
    payload = %{typing: false}
    update_presence_state(topic, key, payload)
  end

  defp update_presence_state(topic, key, payload) do
    metas =
      Presence.get_by_key(topic, key)[:metas]
      |> hd
      |> Map.merge(payload)

    Presence.update(self(), topic, key, metas)
  end

  defp create_timestamp(timezone) do
    timestamp =
      DateTime.now(timezone, Tzdata.TimeZoneDatabase)
      |> elem(1)
      |> Time.to_string()
      |> String.split(".")
      |> hd

    highlight_style =
      case timestamp =~ "04:20:" || timestamp =~ "16:20:" do
        true -> "text-green-400"
        false -> "text-blue-500"
      end

    %{
      value: timestamp,
      class: highlight_style
    }
  end
end
