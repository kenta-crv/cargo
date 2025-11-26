# config/initializers/sidekiq_cron.rb

# タイムゾーンをJSTに設定していることを確認してください。
Sidekiq::Cron::Job.load_from_hash({
  # 01:00から07:59まで、12分ごとに ArticleSchedulerJob を実行
  'article_generation_scheduler': {
    'class' => 'ArticleSchedulerJob',
    'cron'  => '*/12 1-7 * * *', 
    'queue' => 'default',
    'description' => '12分ごとに本文生成待ちの記事をキューに投入する'
  }
})
