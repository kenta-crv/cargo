# app/workers/generate_column_body_job.rb

# GptArticleGenerator クラスがlib/ などに定義されている前提

class GenerateColumnBodyJob
  include Sidekiq::Worker

  # 記事生成専用のキューを使用
  sidekiq_options queue: :article_generation, retry: 5, backtrace: true

  # Sidekiqの標準リトライ機能（retry: 5）を利用し、失敗時は指数関数的に待機時間を延長

  def perform(column_id)
    column = Column.find_by(id: column_id)
    return unless column

    # 1. 業務時間内の実行をブロック（深夜集中運用のため）
    current_hour = Time.zone.now.hour
    unless (1..7).include?(current_hour) # 01:00 (1) から 07:59 (7) を許可
      Rails.logger.warn("【SKIP】記事ID:#{column_id} は業務時間外（01:00-08:00）に実行されてしまったためスキップします。")
      # ジョブを再キューイングするか、デッドにするか、ビジネス要件に合わせて調整します
      # ここでは一旦、すぐにリトライさせず、次の深夜帯を待つためにエラーを発生させます
      # raise StandardError.new("Execution outside of allowed time (01:00-08:00)") 
      # 今回はジョブの滞留を避けるため、一旦ログで警告に留めます。
      return
    end

    Rails.logger.info("記事ID:#{column_id} の本文生成を開始します。")

    # 2. 本文生成の実行
    # GptArticleGenerator の呼び出し
    generated_body = GptArticleGenerator.generate_body(column)

    if generated_body.present?
      # 3. 成功時: 本文を保存し、ステータスを更新
      column.update!(
        body: generated_body,
        status: "published", # または "content_ready" など
        published_at: Time.zone.now
      )
      Rails.logger.info("記事ID:#{column_id} の本文生成と公開ステータスへの更新に成功しました。")
    else
      # 4. 失敗時: ステータスはapprovedのまま（リトライ対象）
      Rails.logger.error("記事ID:#{column_id} の本文生成に失敗しました。Sidekiqの自動リトライを待ちます。")
      
      # GptArticleGeneratorがnilを返した場合、Sidekiqのリトライに乗せるために例外を発生させる
      # これにより、APIのレート制限などで失敗した場合、後で自動リトライされます。
      raise "本文生成ジョブがAPIエラーまたはタイムアウトにより失敗しました。"
    end
  end
end