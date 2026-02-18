require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  test "sign up creates account and redirects to boards" do
    post registration_path, params: {
      user: { email_address: "new@example.com", password: "password123", password_confirmation: "password123" }
    }
    assert_redirected_to boards_path
    assert User.exists?(email_address: "new@example.com")
  end

  test "sign in with valid credentials redirects to boards" do
    User.create!(email_address: "u@example.com", password: "password123")
    post session_path, params: { email_address: "u@example.com", password: "password123" }
    assert_redirected_to root_path
  end

  test "sign in with invalid credentials redirects to login with alert" do
    post session_path, params: { email_address: "nobody@example.com", password: "wrong" }
    assert_redirected_to new_session_path
  end

  test "unauthenticated request to boards redirects to login" do
    get boards_path
    assert_redirected_to new_session_path
  end

  test "log out clears session and redirects to login" do
    user = User.create!(email_address: "u@example.com", password: "password123")
    sign_in_as user
    delete session_path
    assert_redirected_to new_session_path
  end

  test "sign up with mismatched passwords re-renders form" do
    post registration_path, params: {
      user: { email_address: "bad@example.com", password: "password123", password_confirmation: "different" }
    }
    assert_response :unprocessable_entity
  end
end
