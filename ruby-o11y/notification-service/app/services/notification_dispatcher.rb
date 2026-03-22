class NotificationDispatcher
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
    template = TEMPLATES[type]
    # Simulate async processing delay
    sleep(rand(0.02..0.08))

    resolved_subject = subject || (template && template[:subject_template] % payload.symbolize_keys rescue type.humanize)
    channel = template&.dig(:channel) || :email

    notification = Notification.create!(
      notification_type: type,
      recipient: recipient,
      subject: resolved_subject,
      channel: channel.to_s,
      payload: payload,
      status: :processing
    )

    # Simulate sending (log instead of real delivery)
    deliver(notification)

    {
      id: notification.id,
      status: notification.status,
      channel: notification.channel,
      recipient: notification.recipient,
      queued_at: notification.created_at.iso8601
    }
  end

  def self.deliver(notification)
    # Simulate delivery delay
    sleep(rand(0.01..0.05))

    Rails.logger.info("[NotificationDispatcher] Delivered #{notification.notification_type} " \
                      "to #{notification.recipient} via #{notification.channel}")

    notification.update!(status: :delivered, delivered_at: Time.current)
  rescue => e
    Rails.logger.error("[NotificationDispatcher] Failed: #{e.message}")
    notification.update!(status: :failed)
  end

  private_class_method :deliver
end
