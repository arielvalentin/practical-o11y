# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_21_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "notifications", force: :cascade do |t|
    t.string "channel", default: "email", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "notification_type", null: false
    t.jsonb "payload", default: {}
    t.string "recipient", null: false
    t.string "status", default: "pending", null: false
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["notification_type"], name: "index_notifications_on_notification_type"
    t.index ["recipient"], name: "index_notifications_on_recipient"
    t.index ["status"], name: "index_notifications_on_status"
  end
end
