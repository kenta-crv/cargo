Rails.application.routes.draw do
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root to: 'tops#index'
  get 'cargo', to: 'tops#cargo'
  get 'recruit', to: 'tops#recruit'
  get 'app', to: 'tops#app'
  resources :columns do
    collection do
      get :draft         # ドラフト一覧
      post :generate_gemini # Gemini生成ボタンのPOST
      match 'bulk_update_drafts', via: [:post, :patch]
    end
    member do
      patch :approve
    end
  end

  require 'sidekiq/web'
  mount Sidekiq::Web, at: "/sidekiq"
end
