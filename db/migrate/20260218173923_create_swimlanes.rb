class CreateSwimlanes < ActiveRecord::Migration[8.0]
  def change
    create_table :swimlanes do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.references :board, null: false, foreign_key: true
      t.timestamps
    end
  end
end
