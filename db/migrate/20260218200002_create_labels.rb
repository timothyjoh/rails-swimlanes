class CreateLabels < ActiveRecord::Migration[8.0]
  def change
    create_table :labels do |t|
      t.string :color, null: false
      t.timestamps
    end
    add_index :labels, :color, unique: true
  end
end
