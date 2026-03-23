Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :recommendations, only: [:index]
      resource :health, only: [:show], controller: "health"
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
