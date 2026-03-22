class OrderNotificationSubscriber
  TRACER = OpenTelemetry.tracer_provider.tracer("store")

  def order_finalized(event)
    order = event.payload[:order]
    return unless order

    TRACER.in_span("OrderNotificationSubscriber order finalized", attributes: {
      "order.number" => order.number.to_s,
      "notification.type" => "order_placed"
    }) do |span|
      NotificationClient.new.order_placed(order)
    end
  rescue NotificationClient::NotificationError => e
    Rails.logger.warn("[OrderNotificationSubscriber] #{e.message}")
  end

  def shipment_shipped(event)
    shipment = event.payload[:shipment]
    return unless shipment

    order = shipment.order
    TRACER.in_span("OrderNotificationSubscriber shipment shipped", attributes: {
      "order.number" => order.number.to_s,
      "notification.type" => "order_shipped",
      "shipment.tracking" => shipment.tracking.to_s
    }) do |span|
      NotificationClient.new.order_shipped(order, shipment)
    end
  rescue NotificationClient::NotificationError => e
    Rails.logger.warn("[OrderNotificationSubscriber] #{e.message}")
  end
end
