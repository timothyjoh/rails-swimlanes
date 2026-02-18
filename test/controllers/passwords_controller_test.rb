require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "new renders password reset form" do
    get new_password_path
    assert_response :success
  end

  test "edit with invalid token redirects to new password path" do
    get edit_password_path("invalid-token")
    assert_redirected_to new_password_path
  end
end
