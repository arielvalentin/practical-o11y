class ShippingClient
  class ShippingError < StandardError; end

  TRACER = OpenTelemetry.tracer_provider.tracer("store")

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
    TRACER.in_span("ShippingClient calculate rates", kind: :client, attributes: {
      "peer.service" => "shipping-service",
      "shipping.origin.zip" => origin[:zip].to_s,
      "shipping.destination.zip" => destination[:zip].to_s,
      "shipping.package.weight" => package[:weight].to_f
    }) do |span|
      begin
        response = @connection.post("/api/v1/rates") do |req|
          req.body = {
            origin: origin,
            destination: destination,
            package: package
          }
        end

        span.set_attribute("http.response.status_code", response.status)
        response.body
      rescue Faraday::Error => e
        span.record_exception(e)
        span.status = OpenTelemetry::Trace::Status.error(e.message)
        Rails.logger.error("[ShippingClient] Failed to fetch rates: #{e.message}")
        raise ShippingError, "Unable to calculate shipping rates: #{e.message}"
      end
    end
  end
end
