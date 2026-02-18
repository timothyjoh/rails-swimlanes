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

ActiveRecord::Schema[8.1].define(version: 2026_02_18_220550) do
  create_table "board_memberships", force: :cascade do |t|
    t.integer "board_id", null: false
    t.datetime "created_at", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["board_id", "user_id"], name: "index_board_memberships_on_board_id_and_user_id", unique: true
    t.index ["board_id"], name: "index_board_memberships_on_board_id"
    t.index ["user_id"], name: "index_board_memberships_on_user_id"
  end

  create_table "boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_boards_on_user_id"
  end

  create_table "card_labels", force: :cascade do |t|
    t.integer "card_id", null: false
    t.datetime "created_at", null: false
    t.integer "label_id", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id", "label_id"], name: "index_card_labels_on_card_id_and_label_id", unique: true
    t.index ["card_id"], name: "index_card_labels_on_card_id"
    t.index ["label_id"], name: "index_card_labels_on_label_id"
  end

  create_table "cards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "swimlane_id", null: false
    t.datetime "updated_at", null: false
    t.index ["swimlane_id"], name: "index_cards_on_swimlane_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["color"], name: "index_labels_on_color", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "swimlanes", force: :cascade do |t|
    t.integer "board_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["board_id"], name: "index_swimlanes_on_board_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "board_memberships", "boards"
  add_foreign_key "board_memberships", "users"
  add_foreign_key "boards", "users"
  add_foreign_key "card_labels", "cards"
  add_foreign_key "card_labels", "labels"
  add_foreign_key "cards", "swimlanes"
  add_foreign_key "sessions", "users"
  add_foreign_key "swimlanes", "boards"
end
