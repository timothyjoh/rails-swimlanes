class AddNotNullToBoards < ActiveRecord::Migration[8.1]
  def change
    change_column_null :boards, :name, false, ""
  end
end
