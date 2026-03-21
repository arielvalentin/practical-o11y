class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.string :notification_type, null: false
      t.string :recipient, null: false
      t.string :subject
      t.string :channel, null: false, default: "email"
      t.string :status, null: false, default: "pending"
      t.jsonb :payload, default: {}
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :notifications, :notification_type
    add_index :notifications, :recipient
    add_index :notifications, :status
    add_index :notifications, :created_at
  end
end
