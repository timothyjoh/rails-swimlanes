class CardsController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_board
  before_action :set_swimlane
  before_action :set_card, only: [:show, :edit, :update, :destroy]

  def show
    @labels = Label.all.order(:color)
  end

  def create
    @card = @swimlane.cards.build(card_params)
    if @card.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@swimlane, :new_card_form),
            partial: "cards/new_form",
            locals: { board: @board, swimlane: @swimlane, card: @card }
          ), status: :unprocessable_entity
        end
        format.html { redirect_to @board, alert: @card.errors.full_messages.to_sentence, status: :unprocessable_entity }
      end
    end
  end

  def edit
    render partial: "cards/edit_form", locals: { board: @board, swimlane: @swimlane, card: @card }
  end

  def update
    if @card.update(card_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            dom_id(@card, :name),
            partial: "cards/edit_form",
            locals: { board: @board, swimlane: @swimlane, card: @card }
          ), status: :unprocessable_entity
        end
        format.html { redirect_to @board, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @card.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@card)) }
      format.html { redirect_to @board }
    end
  end

  def reorder
    card = Card.find(params[:card_id])
    # Verify card belongs to current user's board chain
    unless Board.accessible_by(Current.user).joins(swimlanes: :cards).where(cards: { id: card.id }).exists?
      raise ActiveRecord::RecordNotFound
    end

    target_position = params[:position].to_i

    # Query destination cards before moving (avoids identity-map ambiguity)
    cards = @swimlane.cards.where.not(id: card.id).order(:position).to_a
    target_position = [[target_position, 0].max, cards.length].min
    card.update!(swimlane_id: @swimlane.id)

    # Rebuild positions in destination swimlane
    cards.insert(target_position, card)
    cards.each_with_index { |c, i| c.update_columns(position: i) }

    head :ok
  end

  private

  def set_board
    @board = Board.accessible_by(Current.user).find(params[:board_id])
  end

  def set_swimlane
    @swimlane = @board.swimlanes.find(params[:swimlane_id])
  end

  def set_card
    @card = @swimlane.cards.find(params[:id])
  end

  def card_params
    params.require(:card).permit(:name, :description, :due_date, label_ids: [])
  end
end
