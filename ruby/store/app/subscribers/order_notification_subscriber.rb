class OrderNotificationSubscriber
  include Spree::Event::Subscriber

  event_action :order_finalized
  event_action :shipment_shipped

  def order_finalized(event)
    order = event.payload[:order]
    return unless order

    NotificationClient.new.order_placed(order)
  rescue NotificationClient::NotificationError => e
    Rails.logger.warn("[OrderNotificationSubscriber] #{e.message}")
  end

  def shipment_shipped(event)
    shipment = event.payload[:shipment]
    return unless shipment

    order = shipment.order
    NotificationClient.new.order_shipped(order, shipment)
  rescue NotificationClient::NotificationError => e
    Rails.logger.warn("[OrderNotificationSubscriber] #{e.message}")
  end
end
