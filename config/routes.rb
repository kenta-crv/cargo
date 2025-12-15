# config/routes.rb

Rails.application.routes.draw do
  # Deviseの管理者認証
  devise_for :admins, controllers: {
    sessions: 'admins/sessions',
    registrations: 'admins/registrations'
  }
  
  root to: 'tops#index'
  get 'cargo', to: 'tops#cargo'
  get 'security', to: 'tops#security'
  get 'construction', to: 'tops#construction'
  get 'cleaning', to: 'tops#cleaning'
  get 'event', to: 'tops#event'
  get 'logistics', to: 'tops#logistics'
  get 'recruit', to: 'tops#recruit'
  get 'app', to: 'tops#app'
  
  resources :columns do
    collection do
      get :draft            # ドラフト一覧
      post :generate_gemini # Gemini生成ボタンのPOST
      match 'bulk_update_drafts', via: [:post, :patch]
    end
    member do
      patch :approve
    end
  end

  # =========================================================
  # 🚨 修正箇所: Sidekiq Web UIを管理者認証で保護する
  # =========================================================
  require 'sidekiq/web'
  
  # Deviseの認証ヘルパー `authenticate` を使用し、
  # 現在のユーザーが 'admin' としてログインしている場合のみ許可する
  authenticate :admin do 
    mount Sidekiq::Web, at: "/sidekiq"
  end
  # =========================================================

end