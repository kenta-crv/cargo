class ColumnsController < ApplicationController
  #before_action :authenticate_admin!, except: [:index, :show]

def index
  if params[:status].present?
    @columns = Column.where(status: params[:status]).where.not(status: "draft").order(updated_at: :desc)
  else
    @columns = Column.where.not(status: "draft").order(updated_at: :desc)
  end
end

  # GET /columns/:id
  def show
    @column = Column.find_by(id: params[:id])

    if @column.nil?
      redirect_to columns_path, alert: "指定された記事が見つかりませんでした。"
      return
    end

    # 1. Markdown本文を取得 (生成プログラムがMarkdownで出力したテキスト)
    markdown_body = @column.body.present? ? @column.body :
      "## 記事はまだ生成されていません。\n\n[編集]画面からテーマ生成を行い、[承認]ボタンを押して本文生成ジョブを実行してください。"

    # =======================================================
    # 2. 【最重要修正点】MarkdownをHTMLに変換する
    # =======================================================
    # KramdownなどのMarkdownパーサーを使ってHTMLに変換
    # ⚠️ kramdown gemのインストールが必要です
    raw_html_body = Kramdown::Document.new(markdown_body).to_html
    
    # 3. HTML化された本文に対して、ID付与と目次抽出を行う
    
    # 不要な inline style や <span> タグを除去
    sanitized_html_body = raw_html_body.gsub(/<span[^>]*>|<\/span>/, '')
                                       .gsub(/ style=\"[^\"]*\"/, '')

    @headings = []
    
    # HTMLタグ (h2, h3, h4) を検索し、IDを付与しつつ目次情報を収集する
    # この正規表現は、HTMLタグになった後で初めて機能します。
    @column_body_with_ids = sanitized_html_body.gsub(/<(h[2-4])>(.*?)<\/\1>/m) do |match|
      if match =~ /<(h[2-4])>(.*?)<\/\1>/m
        tag = $1 # 例: "h2"
        text = $2 # 例: "古代ローマ建築の基礎"
        
        idx = @headings.size
        # HTMLタグからテキストとレベルを抽出
        @headings << { tag: tag, text: text, id: "heading-#{idx}", level: tag[1].to_i }
        
        # 抽出した見出しにIDを付与して本文を置換
        "<#{tag} id='heading-#{idx}'>#{text}</#{tag}>"
      else
        match
      end
    end
    
  end

  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)
    if @column.save
      redirect_to columns_path
    else
      render 'new'
    end
  end

  def edit
    @column = Column.find(params[:id])
    add_breadcrumb "記事編集", edit_column_path
  end

  def destroy
    @column = Column.find(params[:id])
    @column.destroy
     redirect_to columns_path
  end

  def update
    @column = Column.find(params[:id])
    if @column.update(column_params)
      redirect_to columns_path
    else
      render 'edit'
    end
  end

    # ▼ ① Gemini自動生成（UIボタンから呼ばれる）
  def generate_gemini
    # params[:batch]が渡されていればその値を使い、なければデフォルトの5を使う
    # params[:batch]は文字列なので、to_iで整数に変換して渡す
    batch = params[:batch] || 20
    created = GeminiColumnGenerator.generate_columns(batch_count: batch.to_i)
    # 実際に何件作成できたかはGeminiColumnGeneratorからは返されていないため、
    # ここでは仮にbatchの回数を使っている可能性があります。
    # created変数が正しくない場合は、GeminiColumnGeneratorの戻り値を修正する必要があります。
    redirect_to draft_columns_path, notice: "#{created}件生成しました"
  end



  # ▼ ② ドラフト一覧
  def draft
    @columns = Column.where(status: "draft").order(created_at: :desc)
  end

def approve
  @column = Column.find(params[:id])
  unless @column.approved?
    @column.update!(status: "approved")
  end
  GenerateColumnBodyJob.perform_later(@column.id)
  #GenerateColumnBodyJob.perform_now(@column.id)
  redirect_to columns_path, notice: "承認しました。本文生成を開始します。"
end

# ▼ ③ 一括操作（承認/削除）
  def bulk_update_drafts
    # 選択されたIDの配列を取得
    column_ids = params[:column_ids]

    # IDが何も選択されていない場合はエラーメッセージを表示してリダイレクト
    unless column_ids.present?
      redirect_to draft_columns_path, alert: "操作対象のドラフトが選択されていません。"
      return
    end

    # 実行する操作の種類をparams[:action_type]から判断
    case params[:action_type]
    when "approve_bulk"
      # 一括承認処理
      columns = Column.where(id: column_ids)
      columns.each do |column|
        unless column.approved?
          column.update!(status: "approved")
          # 個別のジョブを発行
          GenerateColumnBodyJob.perform_later(column.id)
          #GenerateColumnBodyJob.perform_now(column.id)
        end
      end
      redirect_to columns_path, notice: "#{columns.count}件のドラフトを承認し、本文生成を開始しました。"

    when "delete_bulk"
      # 一括削除処理
      count = Column.where(id: column_ids).destroy_all
      redirect_to draft_columns_path, notice: "#{count}件のドラフトを削除しました。"

    else
      redirect_to draft_columns_path, alert: "無効な操作が選択されました。"
    end
  end

  private
  def column_params
    params.require(:column).permit(
      :title, #タイトル
      :file,  #写真
      :choice,  #カテゴリー
      :keyword, #キーワード
      :description, #説明
      :body #本文
      )
    end
  end
