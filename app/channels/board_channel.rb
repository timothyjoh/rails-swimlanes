class BoardChannel < Turbo::StreamsChannel
  def subscribed
    verified_stream_name = Turbo.signed_stream_verifier.verified(params[:signed_stream_name])
    return reject unless verified_stream_name

    board = GlobalID::Locator.locate(verified_stream_name)
    return reject unless board.is_a?(Board) && BoardMembership.exists?(board: board, user: current_user)

    stream_from verified_stream_name
  end
end
