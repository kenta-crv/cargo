# app/services/gemini_column_generator.rb
class GeminiColumnGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  def self.generate_columns(batch_count: 100)
    batch_count.times do
      prompt = "軽貨物配送サービスに関するブログ記事のテーマ、記事概要、SEOキーワード、およびカテゴリを日本語で生成してください。求職者に向けた発信ではありません。"

      response_json_string = post_to_gemini(prompt)
      next unless response_json_string

      begin
        data = JSON.parse(response_json_string)

        Column.create!(
          title:       data["title"],
          description: data["description"],
          keyword:     data["keyword"],
          choice:      data["choice"], 
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


  def self.post_to_gemini(prompt)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")

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
            "choice":    { "type": "string" }
          },
          "required": ["title", "description", "keyword", "choice"]
        }
      }
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http|
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
