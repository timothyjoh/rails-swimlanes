Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [:new, :create]

  resources :boards
  root "boards#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
