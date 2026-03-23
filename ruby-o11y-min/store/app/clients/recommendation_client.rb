class RecommendationClient
  class RecommendationError < StandardError; end

  def initialize(base_url: ENV.fetch("RECOMMENDATION_SERVICE_URL", "http://localhost:3002"))
    @connection = Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.options.timeout = 10
      f.options.open_timeout = 5
    end
  end

  def recommendations_for(product_id:, limit: 4)
    response = @connection.get("/api/v1/recommendations", {
      product_id: product_id,
      limit: limit
    })

    response.body
  rescue Faraday::Error => e
    Rails.logger.error("[RecommendationClient] Failed to fetch recommendations: #{e.message}")
    raise RecommendationError, "Unable to fetch recommendations: #{e.message}"
  end
end
