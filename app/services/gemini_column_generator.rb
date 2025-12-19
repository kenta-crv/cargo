# app/services/gemini_column_generator.rb
class GeminiColumnGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  # 安定性の高い1.5-flashを使用
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  GENRE_CONFIG = {
    cargo: {
      service_name:  "軽貨物配送サービス",
      service_brand: "OK配送",
      service_path:  "/cargo",
      target: "軽貨物事業者との取引や協業を検討している企業の担当者または経営層（荷主企業やITベンダーなど）",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "求職者および軽貨物事業者自身に向けた発信"
    },
    security: {
      service_name:  "警備業務",
      service_brand: "OK警備",
      service_path:  "/security",
      target: "警備業務の外注や切替を検討している企業・施設管理者",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "警備員の求人や資格取得を目的とした発信"
    },
    cleaning: {
      service_name:  "清掃業務",
      service_brand: "OK清掃",
      service_path:  "/cleaning",
      target: "清掃業務の外注を検討している法人・施設管理者",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "清掃スタッフの求人向け発信"
    },
    app: {
      service_name:  "テレアポ型営業代行",
      service_brand: "アポ匠",
      service_path:  "/app",
      target: "新規商談獲得を外注したいBtoB企業の責任者",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "成果報酬型営業の訴求"
    },
    ai: {
      service_name:  "AI活用型ブログ・SEO支援",
      service_brand: "AI生成BLOG",
      service_path:  "/ai",
      target: "SEO集客を効率化・内製化したい企業",
      categories: ["課題解決", "導入検討", "業界理解", "活用イメージ", "不安解消"],
      exclude: "個人ブロガー向けの発信"
    },
    construction: {
      service_name:  "建設現場労務支援サービス",
      service_brand: "OK建設",
      service_path:  "/construction",
      target: "建設現場の人手不足に悩む元請・施工会社",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "作業員の求人を目的とした発信"
    }
  }.freeze

  # ==========================================================
  # メインメソッド
  # ==========================================================
  def self.generate_columns(genre: nil, batch_count: 10)
    if genre
      # 特定ジャンルのみ生成する場合
      config = GENRE_CONFIG.fetch(genre.to_sym)
      category_list = config[:categories]
      current_category_index = 0

      batch_count.times do |i|
        target_category = category_list[current_category_index]
        current_category_index = (current_category_index + 1) % category_list.size
        execute_generation(genre.to_sym, target_category)
        
        if i < batch_count - 1
          puts "制限回避のため7秒待機します..."
          sleep 7
        end
      end
    else
      # ジャンル指定なしの場合：全ジャンルを均等に生成
      rounds = (batch_count.to_f / GENRE_CONFIG.size).ceil
      processed_count = 0

      rounds.times do |r|
        GENRE_CONFIG.keys.each do |g|
          break if processed_count >= batch_count
          
          target_category = GENRE_CONFIG[g][:categories].sample
          execute_generation(g, target_category)
          processed_count += 1
          
          if processed_count < batch_count
            puts "制限回避のため7秒待機します..."
            sleep 7
          end
        end
      end
    end
  end

  # ==========================================================
  # 内部実行メソッド（ログ出力あり）
  # ==========================================================
  def self.execute_generation(genre, target_category)
    config = GENRE_CONFIG.fetch(genre)
    puts "--- [#{genre}] 生成開始 カテゴリ: #{target_category} ---"

    prompt = <<~EOS
      #{config[:service_name]}に関する企業向けブログ記事を日本語で作成してください。
      ターゲット読者：#{config[:target]}
      記事カテゴリ：「#{target_category}」
      記事の目的：
      ・#{config[:service_brand]}のサービス内容を自然に理解してもらう
      ・最終的に「問い合わせしてみよう」と思ってもらう
      重要な条件：
      ・#{config[:exclude]}ではありません
      ・売り込みすぎず、実務目線で分かりやすく
      ・記事の最後は「#{config[:service_brand]}（#{config[:service_path]}）では〜」という形で自然に締めてください
      
      keyword項目の制約：
      ・SEOを意識したキーワードを3〜5個選定してください。
      ・必ず「カンマ区切り」の形式で出力してください（例：キーワード1,キーワード2,キーワード3）。
      ・文章や説明文は含めないでください。

      以下のJSON形式で出力してください。
    EOS

    response_json_string = post_to_gemini(prompt)
    
    if response_json_string
      begin
        data = JSON.parse(response_json_string)
        Column.create!(
          title:       data["title"],
          description: data["description"],
          keyword:     data["keyword"],
          choice:      target_category,
          genre:       genre.to_s,
          status:      "draft"
        )
        puts "成功: [#{genre}] #{data["title"]}"
      rescue => e
        puts "エラー: 保存失敗 (#{e.message})"
      end
    else
      puts "警告: APIから応答がありませんでした"
    end
  end

  # =========================
  # Gemini API 実行
  # =========================
  def self.post_to_gemini(prompt)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            title:       { type: "string" },
            description: { type: "string" },
            keyword:     { 
              type: "string",
              description: "Comma-separated SEO keywords only."
            }
          },
          required: %w[title description keyword]
        }
      }
    }.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      if res.is_a?(Net::HTTPSuccess)
        return JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text")
      else
        puts "Gemini API Error: #{res.code}"
        return nil
      end
    rescue => e
      puts "通信エラー: #{e.message}"
      return nil
    end
  end
end