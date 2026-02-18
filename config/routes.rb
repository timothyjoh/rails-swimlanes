Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [:new, :create]

  resources :boards do
    resources :swimlanes, only: [:create, :edit, :update, :destroy] do
      resources :cards, only: [:create, :edit, :update, :destroy] do
          collection do
            patch :reorder
          end
        end
    end
  end
  root "boards#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
