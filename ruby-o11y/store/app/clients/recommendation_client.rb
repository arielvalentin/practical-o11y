class RecommendationClient
  class RecommendationError < StandardError; end

  TRACER = OpenTelemetry.tracer_provider.tracer("store")

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
    TRACER.in_span("RecommendationClient fetch recommendations", kind: :client, attributes: {
      "peer.service" => "recommendation-service",
      "recommendation.product_id" => product_id.to_s,
      "recommendation.limit" => limit
    }) do |span|
      begin
        response = @connection.get("/api/v1/recommendations", {
          product_id: product_id,
          limit: limit
        })

        span.set_attribute("http.response.status_code", response.status)
        response.body
      rescue Faraday::Error => e
        span.record_exception(e)
        span.status = OpenTelemetry::Trace::Status.error(e.message)
        Rails.logger.error("[RecommendationClient] Failed to fetch recommendations: #{e.message}")
        raise RecommendationError, "Unable to fetch recommendations: #{e.message}"
      end
    end
  end
end
