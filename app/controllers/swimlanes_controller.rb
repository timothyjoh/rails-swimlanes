class SwimlanesController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_board
  before_action :set_swimlane, only: [:edit, :header, :update, :destroy]

  def create
    @swimlane = @board.swimlanes.build(swimlane_params)
    if @swimlane.save
      Turbo::StreamsChannel.broadcast_append_to(
        @board,
        target: "swimlanes",
        partial: "swimlanes/swimlane",
        locals: { swimlane: @swimlane, board: @board }
      )
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_swimlane_form", partial: "swimlanes/new_form", locals: { board: @board, swimlane: @swimlane }), status: :unprocessable_entity }
        format.html { redirect_to @board, status: :unprocessable_entity }
      end
    end
  end

  def header
    render partial: "swimlanes/header", locals: { swimlane: @swimlane, board: @board }
  end

  def edit
    render partial: "swimlanes/edit_form", locals: { board: @board, swimlane: @swimlane }
  end

  def update
    if @swimlane.update(swimlane_params)
      Turbo::StreamsChannel.broadcast_replace_to(
        @board,
        target: dom_id(@swimlane, :header),
        partial: "swimlanes/header",
        locals: { swimlane: @swimlane, board: @board }
      )
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@swimlane, :edit_form), partial: "swimlanes/edit_form", locals: { board: @board, swimlane: @swimlane }), status: :unprocessable_entity }
        format.html { redirect_to @board, status: :unprocessable_entity }
      end
    end
  end

  def reorder
    swimlane = @board.swimlanes.find(params[:swimlane_id])
    target_position = params[:position].to_i

    swimlanes = @board.swimlanes.where.not(id: swimlane.id).order(:position).to_a
    target_position = [[target_position, 0].max, swimlanes.length].min
    swimlanes.insert(target_position, swimlane)
    swimlanes.each_with_index { |s, i| s.update_columns(position: i) }

    head :ok
  end

  def destroy
    if @swimlane.destroy
      Turbo::StreamsChannel.broadcast_remove_to(@board, target: dom_id(@swimlane))
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@swimlane)) }
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to @board, alert: @swimlane.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_board
    @board = Board.accessible_by(Current.user).find(params[:board_id])
  end

  def set_swimlane
    @swimlane = @board.swimlanes.find(params[:id])
  end

  def swimlane_params
    params.require(:swimlane).permit(:name)
  end
end
