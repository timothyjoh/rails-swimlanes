class CreateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :cards do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.references :swimlane, null: false, foreign_key: true
      t.timestamps
    end
  end
end
