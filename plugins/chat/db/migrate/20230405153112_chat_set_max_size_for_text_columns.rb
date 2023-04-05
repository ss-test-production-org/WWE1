# frozen_string_literal: true

class ChatSetMaxSizeForTextColumns < ActiveRecord::Migration[7.0]
  DEFAULT_LIMIT = 1_000_000

  def up
    change_column :chat_message_revisions, :new_message, :string, limit: DEFAULT_LIMIT
    change_column :chat_message_revisions, :old_message, :string, limit: DEFAULT_LIMIT
    change_column :chat_messages, :message, :string, limit: 12_000
    change_column :chat_messages, :cooked, :string, limit: DEFAULT_LIMIT
    change_column :chat_drafts, :data, :string, limit: 50_000
    change_column :chat_channels, :description, :string, limit: DEFAULT_LIMIT
  end

  def down
    change_column :chat_message_revisions, :new_message, :text
    change_column :chat_message_revisions, :old_message, :text
    change_column :chat_messages, :message, :text
    change_column :chat_messages, :cooked, :text
    change_column :chat_drafts, :data, :text
    change_column :chat_channels, :description, :text
  end
end
