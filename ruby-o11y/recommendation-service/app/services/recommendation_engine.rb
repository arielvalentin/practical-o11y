class RecommendationEngine
  TRACER = OpenTelemetry.tracer_provider.tracer("recommendation-service")

  # Mock product catalog for generating recommendations
  MOCK_PRODUCTS = [
    { id: "prod_001", name: "Classic T-Shirt", category: "apparel", price: 29.99, score: 0.95 },
    { id: "prod_002", name: "Denim Jacket", category: "apparel", price: 89.99, score: 0.88 },
    { id: "prod_003", name: "Running Shoes", category: "footwear", price: 119.99, score: 0.92 },
    { id: "prod_004", name: "Leather Belt", category: "accessories", price: 39.99, score: 0.85 },
    { id: "prod_005", name: "Wool Sweater", category: "apparel", price: 69.99, score: 0.90 },
    { id: "prod_006", name: "Canvas Sneakers", category: "footwear", price: 59.99, score: 0.87 },
    { id: "prod_007", name: "Sunglasses", category: "accessories", price: 149.99, score: 0.82 },
    { id: "prod_008", name: "Silk Scarf", category: "accessories", price: 45.99, score: 0.78 },
    { id: "prod_009", name: "Chino Pants", category: "apparel", price: 54.99, score: 0.91 },
    { id: "prod_010", name: "Hiking Boots", category: "footwear", price: 139.99, score: 0.89 },
    { id: "prod_011", name: "Baseball Cap", category: "accessories", price: 24.99, score: 0.76 },
    { id: "prod_012", name: "Linen Shirt", category: "apparel", price: 49.99, score: 0.86 }
  ].freeze

  STRATEGIES = %i[similar popular trending].freeze

  def self.recommend(product_id:, limit: 4)
    TRACER.in_span("generate recommendations", attributes: {
      "recommendation.product_id" => product_id.to_s,
      "recommendation.limit" => limit
    }) do |span|
      sleep(rand(0.03..0.10))

      strategy = STRATEGIES.sample
      span.set_attribute("recommendation.strategy", strategy.to_s)

      candidates = generate_candidates(product_id, strategy)

      results = candidates
        .reject { |p| p[:id] == product_id }
        .first(limit)
        .map { |p| format_recommendation(p, strategy) }

      span.set_attribute("recommendation.count", results.size)
      results
    end
  end

  def self.generate_candidates(product_id, strategy)
    case strategy
    when :similar
      source = MOCK_PRODUCTS.find { |p| p[:id] == product_id }
      category = source&.dig(:category) || MOCK_PRODUCTS.sample[:category]
      MOCK_PRODUCTS
        .select { |p| p[:category] == category }
        .sort_by { |p| -p[:score] + rand(-0.1..0.1) }
    when :popular
      MOCK_PRODUCTS.sort_by { |p| -p[:score] + rand(-0.2..0.2) }
    when :trending
      MOCK_PRODUCTS.shuffle
    end
  end

  def self.format_recommendation(product, strategy)
    {
      product_id: product[:id],
      name: product[:name],
      category: product[:category],
      price: product[:price],
      relevance_score: (product[:score] + rand(-0.05..0.05)).round(3),
      strategy: strategy
    }
  end

  private_class_method :generate_candidates, :format_recommendation
end
