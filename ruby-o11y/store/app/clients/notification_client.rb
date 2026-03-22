class NotificationClient
  class NotificationError < StandardError; end

  TRACER = OpenTelemetry.tracer_provider.tracer("store")

  def initialize(base_url: ENV.fetch("NOTIFICATION_SERVICE_URL", "http://localhost:3003"))
    @connection = Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.options.timeout = 10
      f.options.open_timeout = 5
    end
  end

  def send_notification(type:, recipient:, subject: nil, payload: {})
    TRACER.in_span("NotificationClient send notification", kind: :client, attributes: {
      "peer.service" => "notification-service",
      "notification.type" => type.to_s,
      "notification.recipient" => recipient.to_s
    }) do |span|
      begin
        response = @connection.post("/api/v1/notifications") do |req|
          req.body = {
            notification: {
              type: type,
              recipient: recipient,
              subject: subject,
              payload: payload
            }
          }
        end

        span.set_attribute("http.response.status_code", response.status)
        response.body
      rescue Faraday::Error => e
        span.record_exception(e)
        span.status = OpenTelemetry::Trace::Status.error(e.message)
        Rails.logger.error("[NotificationClient] Failed to send notification: #{e.message}")
        raise NotificationError, "Unable to send notification: #{e.message}"
      end
    end
  end

  def order_placed(order)
    send_notification(
      type: "order_placed",
      recipient: order.email,
      payload: {
        order_number: order.number,
        total: order.total.to_s,
        item_count: order.line_items.count
      }
    )
  end

  def order_shipped(order, shipment)
    send_notification(
      type: "order_shipped",
      recipient: order.email,
      payload: {
        order_number: order.number,
        carrier: shipment.shipping_method&.name || "Standard",
        tracking_number: shipment.tracking || "N/A"
      }
    )
  end
end
