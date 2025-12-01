# app/services/gemini_column_generator.rb
class GeminiColumnGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  def self.generate_columns(batch_count: 100)
    # ターゲット読者（取引したい企業）の関心事に合わせたカテゴリリスト
    category_list = ["軽貨物パートナー選定", "物流DX・技術連携", "発注リスクと法令遵守", "市場トレンドと展望", "コスト最適化・事例"]
    
    max_retries = 3 # 🚨 504対策：最大リトライ回数

    batch_count.times do
      # 🚨 プロンプト：ターゲット、多様性、難易度の制限をすべて明記
      prompt = <<~EOS
        軽貨物配送サービスに関するブログ記事のテーマ、記事概要、SEOキーワード、およびカテゴリを日本語で生成してください。
        
        ターゲット読者は**軽貨物事業者との取引や協業を検討している企業の担当者または経営層（荷主企業やITベンダーなど）**です。
        
        【最重要指示1：多様性と難易度】
        生成するテーマは、**以下のカテゴリリストから幅広く（均等になるように）**選んでください。
        また、テーマは**業界の専門家以外でも理解でき、実務に役立つ汎用的な内容**に限定し、**難易度が高すぎる専門的な議論や学術的な議題は避けてください**。
        
        【最重要指示2：目的】
        彼らが発注や提携の意思決定に役立つ、軽貨物事業者の選定基準、メリット、市場動向、リスク管理に関する内容を抽出してください。
        
        求職者および軽貨物事業者自身に向けた発信ではありません。
        
        カテゴリは以下のリストから必ず1つ選択してください: #{category_list.join(", ")}
      EOS
      
      response_json_string = nil
      
      # 🚨 504対策：リトライ処理の導入
      max_retries.times do |attempt|
        response_json_string = post_to_gemini(prompt, category_list)
        break if response_json_string # 成功したらループを抜ける
        
        # 失敗した場合、最後の試行でなければ待機して再試行
        if attempt < max_retries - 1
          sleep_time = 2 ** attempt # 指数バックオフ
          Rails.logger.warn("Gemini API呼び出し失敗 (試行#{attempt + 1}/#{max_retries})。#{sleep_time}秒待機してリトライします。")
          sleep(sleep_time) 
        end
      end
      
      next unless response_json_string

      begin
        data = JSON.parse(response_json_string)

        Column.create!(
          title:       data["title"],
          description: data["description"],
          keyword:     data["keyword"],
          choice:      data["category"], 
          status:      "draft"
        )

      rescue JSON::ParserError => e
        Rails.logger.error("JSONパースエラー: #{e.message} - Response: #{response_json_string}")
        next
      rescue => e
        Rails.logger.error("データベース保存エラー: #{e.message}")
        next
      end
    end
  end


  # JSONスキーマと504対策（タイムアウト延長）
  def self.post_to_gemini(prompt, category_list = nil)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")

    category_schema = { "type": "string" }
    category_schema["enum"] = category_list if category_list.present? 

    req.body = {
      contents: [ { parts: [ { text: prompt } ] } ],
      generationConfig: {
        "responseMimeType": "application/json",
        "responseSchema": {
          "type": "object",
          "properties": {
            "title":       { "type": "string" },
            "description": { "type": "string" },
            "keyword":     { "type": "string" },
            "category":    category_schema
          },
          "required": ["title", "description", "keyword", "category"]
        }
      }
    }.to_json

    # 🚨 504対策：read_timeoutを120秒に延長
    res = Net::HTTP.start(uri.hostname, uri.port, 
                          use_ssl: true, 
                          verify_mode: OpenSSL::SSL::VERIFY_NONE,
                          read_timeout: 120) do |http| 
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      api_response = JSON.parse(res.body)
      api_response.dig("candidates", 0, "content", "parts", 0, "text")
    else
      Rails.logger.error("Gemini API error (Status: #{res.code}): #{res.body}")
      nil
    end
  end
end