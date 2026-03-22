class NotificationDispatcher
  TRACER = OpenTelemetry.tracer_provider.tracer("notification-service")

  TEMPLATES = {
    "order_placed" => {
      channel: :email,
      subject_template: "Order #%{order_number} confirmed",
      body_template: "Thank you for your order! Your order #%{order_number} has been placed and is being processed."
    },
    "order_shipped" => {
      channel: :email,
      subject_template: "Order #%{order_number} shipped",
      body_template: "Your order #%{order_number} has been shipped via %{carrier}. Tracking: %{tracking_number}"
    },
    "order_delivered" => {
      channel: :email,
      subject_template: "Order #%{order_number} delivered",
      body_template: "Your order #%{order_number} has been delivered. We hope you enjoy your purchase!"
    },
    "password_reset" => {
      channel: :email,
      subject_template: "Password reset requested",
      body_template: "Click the link to reset your password. This link expires in 24 hours."
    },
    "welcome" => {
      channel: :email,
      subject_template: "Welcome to our store!",
      body_template: "Welcome, %{name}! Thank you for creating an account."
    }
  }.freeze

  def self.dispatch(type:, recipient:, subject: nil, payload: {})
    TRACER.in_span("dispatch notification", attributes: {
      "notification.type" => type.to_s,
      "notification.recipient" => recipient.to_s
    }) do |span|
      template = TEMPLATES[type]
      sleep(rand(0.02..0.08))

      resolved_subject = subject || (template && template[:subject_template] % payload.symbolize_keys rescue type.humanize)
      channel = template&.dig(:channel) || :email
      span.set_attribute("notification.channel", channel.to_s)

      notification = Notification.create!(
        notification_type: type,
        recipient: recipient,
        subject: resolved_subject,
        channel: channel.to_s,
        payload: payload,
        status: :processing
      )

      span.set_attribute("notification.id", notification.id)
      deliver(notification)

      {
        id: notification.id,
        status: notification.status,
        channel: notification.channel,
        recipient: notification.recipient,
        queued_at: notification.created_at.iso8601
      }
    end
  end

  def self.deliver(notification)
    TRACER.in_span("deliver notification", attributes: {
      "notification.id" => notification.id,
      "notification.type" => notification.notification_type,
      "notification.channel" => notification.channel
    }) do |span|
      sleep(rand(0.01..0.05))

      Rails.logger.info("[NotificationDispatcher] Delivered #{notification.notification_type} " \
                        "to #{notification.recipient} via #{notification.channel}")

      notification.update!(status: :delivered, delivered_at: Time.current)
      span.set_attribute("notification.status", "delivered")
    end
  rescue => e
    span = OpenTelemetry::Trace.current_span
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error(e.message)
    Rails.logger.error("[NotificationDispatcher] Failed: #{e.message}")
    notification.update!(status: :failed)
  end

  private_class_method :deliver
end
