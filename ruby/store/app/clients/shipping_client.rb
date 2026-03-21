class ShippingClient
  class ShippingError < StandardError; end

  def initialize(base_url: ENV.fetch("SHIPPING_SERVICE_URL", "http://localhost:3001"))
    @connection = Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.options.timeout = 10
      f.options.open_timeout = 5
    end
  end

  def calculate_rates(origin:, destination:, package:)
    response = @connection.post("/api/v1/rates") do |req|
      req.body = {
        origin: origin,
        destination: destination,
        package: package
      }
    end

    response.body
  rescue Faraday::Error => e
    Rails.logger.error("[ShippingClient] Failed to fetch rates: #{e.message}")
    raise ShippingError, "Unable to calculate shipping rates: #{e.message}"
  end
end
