# app/jobs/article_scheduler_job.rb
class ArticleSchedulerJob
  include Sidekiq::Worker
  
  # スケジューラー自体は高優先度で実行して問題ありません
  sidekiq_options queue: :default 

  def perform
    # 0. 実行時間のチェックは不要（sidekiq-cronで制御されるため）
    
    # 1. 現在、本文生成待ち（approved）のColumnを取得
    # approvedステータスは、Contollerのapproveアクションで設定されます。
    columns_to_generate = Column.where(status: "approved").order(created_at: :asc).limit(5)
    
    if columns_to_generate.empty?
      Rails.logger.info("現在、本文生成待ちの 'approved' 記事はありません。")
      return
    end

    Rails.logger.info("本文生成待ちの記事を #{columns_to_generate.count} 件発見しました。")
    
    # 2. 記事ごとに本文生成Workerをキューに投入
    columns_to_generate.each do |column|
      # GenerateColumnBodyJob は sidekiq_options で article_generation キューを使う
      GenerateColumnBodyJob.perform_async(column.id)
      Rails.logger.info("記事ID:#{column.id} の本文生成ジョブをキューに投入しました。")
    end
  end
end