# frozen_string_literal: true

namespace :articles do
  desc "ドラフト記事の中から古いものから順に最大4件選び、Sidekiqキューに投入する"
  task enqueue_daily_generation: :environment do
    # 1日あたりに処理したい記事の最大件数
    DAILY_LIMIT = 4

    # 処理対象となる記事を取得
    # 条件:
    # 1. status が 'draft' のもの
    # 2. 作成日時 (created_at) が古いものから優先的に処理するため、昇順で並び替える
    # 3. 最大件数 (DAILY_LIMIT) に制限する
    draft_columns = Column.where(status: 'draft').order(created_at: :asc).limit(DAILY_LIMIT)

    if draft_columns.empty?
      Rails.logger.info("【DailyScheduler】処理対象のドラフト記事はありませんでした。")
      next # 処理を終了
    end

    Rails.logger.info("【DailyScheduler】本日、#{draft_columns.size}件の記事生成をキューに投入します。")

    draft_columns.each do |column|
      # Sidekiqワーカーに記事IDを渡し、非同期で実行依頼
      ArticleGenerationWorker.perform_async(column.id)
      
      # キューに投入したら、ステータスを 'queued' などに更新しておくと、次回実行時に重複して取得されるのを防げますが、
      # ArticleGenerationWorker内で 'generating' に更新するロジックがあるため、ここでは必須ではありません。
      # 今回はシンプルに、ワーカー内のロックに任せます。
      Rails.logger.info("  -> Column ID: #{column.id} (Title: #{column.title.truncate(30)}) をキューに投入しました。")
    end

    Rails.logger.info("【DailyScheduler】本日の記事生成キューイング処理が完了しました。")
  end
end

# 実行方法 (例: サーバーのターミナルで実行、またはCron/Schedulerサービスから実行)
# bundle exec rake articles:enqueue_daily_generation