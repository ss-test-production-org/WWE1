# frozen_string_literal: true

class PollsSetMaxSizeForTextColumns < ActiveRecord::Migration[7.0]
  def up
    change_column :poll_options, :html, :string, limit: 10_000
  end

  def down
    change_column :poll_options, :html, :text
  end
end
