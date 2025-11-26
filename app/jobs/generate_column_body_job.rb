# app/jobs/generate_column_body_job.rb

class GenerateColumnBodyJob < ApplicationJob
  # 🚨 修正1: 記事生成専用キューに変更
  queue_as :article_generation

  def perform(column_id)
    # find_byではなくfindを使用する場合、レコードが存在しない場合はActiveRecord::RecordNotFoundが発生し、
    # Sidekiqの標準機能でリトライされるため、nilチェックは不要となります（今回はfindを使用）。
    column = Column.find(column_id)
    
    # 承認済み（approved）の記事のみを対象とする（Controllerでapprovedに設定済み）
    return unless column.status == "approved" 
    
    Rails.logger.info("記事ID:#{column.id} の本文生成を開始します。")

    # 本文生成ロジックを呼び出す
    body = GptArticleGenerator.generate_body(column)

    if body.present?
      # 🚨 修正2: 本文保存とステータスを公開済み（published）に更新
      column.update!(
        body: body,
        status: "published",
        published_at: Time.zone.now
      )
      Rails.logger.info("記事ID:#{column.id} の本文生成と公開ステータスへの更新に成功しました。")
    else
      # 🚨 修正3: 本文生成失敗時、Active Jobのリトライ機能に乗せるために例外を発生させる
      error_message = "GPT本文生成失敗 (APIエラー/タイムアウト) ColumnID: #{column.id}"
      Rails.logger.error(error_message)
      # 例外を発生させると、Sidekiq（Active Job）が設定された回数リトライを試みます
      raise StandardError, error_message
    end
  end
end