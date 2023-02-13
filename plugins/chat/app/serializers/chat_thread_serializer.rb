# frozen_string_literal: true

class ChatThreadSerializer < ApplicationSerializer
  has_one :original_message_user, serializer: BasicUserWithStatusSerializer, embed: :objects
  has_one :original_message, serializer: ChatThreadOriginalMessageSerializer, embed: :objects

  attributes :id, :title, :status, :messages

  def messages
    ActiveModel::ArraySerializer.new(
      object.chat_messages.order(:created_at).last(50),
      each_serializer: ChatMessageSerializer,
      chat_channel: object.channel,
      scope: scope,
    )
  end
end
