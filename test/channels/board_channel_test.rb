require "test_helper"

class BoardChannelTest < ActionCable::Channel::TestCase
  setup do
    @owner = User.create!(email_address: "owner@board_channel.com", password: "pass1234", password_confirmation: "pass1234")
    @board = Board.create!(name: "Test Board", user: @owner)
    BoardMembership.create!(board: @board, user: @owner, role: :owner)
    @signed_stream_name = Turbo.signed_stream_verifier.generate(@board.to_gid_param)
  end

  test "member can subscribe" do
    stub_connection current_user: @owner
    subscribe signed_stream_name: @signed_stream_name
    assert_has_stream @board.to_gid_param
  end

  test "non-member subscription is rejected" do
    stranger = User.create!(email_address: "stranger@board_channel.com", password: "pass1234", password_confirmation: "pass1234")
    stub_connection current_user: stranger
    subscribe signed_stream_name: @signed_stream_name
    assert subscription.rejected?
  end

  test "nil user subscription is rejected" do
    stub_connection current_user: nil
    subscribe signed_stream_name: @signed_stream_name
    assert subscription.rejected?
  end

  test "invalid signed stream name is rejected" do
    stub_connection current_user: @owner
    subscribe signed_stream_name: "tampered_value"
    assert subscription.rejected?
  end
end
