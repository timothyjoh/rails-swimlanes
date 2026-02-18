class AddDetailsToCards < ActiveRecord::Migration[8.0]
  def change
    add_column :cards, :description, :text
    add_column :cards, :due_date, :date
  end
end
