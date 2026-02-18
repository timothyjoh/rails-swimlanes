class CreateCardLabels < ActiveRecord::Migration[8.0]
  def change
    create_table :card_labels do |t|
      t.references :card, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true
      t.timestamps
    end
    add_index :card_labels, [:card_id, :label_id], unique: true
  end
end
