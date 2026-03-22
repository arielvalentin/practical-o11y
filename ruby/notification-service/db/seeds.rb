# Seed notification history for demo purposes
puts "Creating sample notifications..."

sample_notifications = [
  {
    notification_type: "order_placed",
    recipient: "alice@example.com",
    subject: "Order #R123456001 confirmed",
    channel: "email",
    status: "delivered",
    payload: { order_number: "R123456001", total: "89.97", item_count: 3 },
    delivered_at: 2.hours.ago
  },
  {
    notification_type: "order_shipped",
    recipient: "alice@example.com",
    subject: "Order #R123456001 shipped",
    channel: "email",
    status: "delivered",
    payload: { order_number: "R123456001", carrier: "UPS", tracking_number: "1Z999AA10123456784" },
    delivered_at: 1.hour.ago
  },
  {
    notification_type: "order_placed",
    recipient: "bob@example.com",
    subject: "Order #R123456002 confirmed",
    channel: "email",
    status: "delivered",
    payload: { order_number: "R123456002", total: "149.99", item_count: 1 },
    delivered_at: 3.hours.ago
  },
  {
    notification_type: "welcome",
    recipient: "carol@example.com",
    subject: "Welcome to our store!",
    channel: "email",
    status: "delivered",
    payload: { name: "Carol" },
    delivered_at: 1.day.ago
  },
  {
    notification_type: "order_placed",
    recipient: "carol@example.com",
    subject: "Order #R123456003 confirmed",
    channel: "email",
    status: "delivered",
    payload: { order_number: "R123456003", total: "234.50", item_count: 5 },
    delivered_at: 30.minutes.ago
  },
  {
    notification_type: "order_shipped",
    recipient: "bob@example.com",
    subject: "Order #R123456002 shipped",
    channel: "email",
    status: "failed",
    payload: { order_number: "R123456002", carrier: "FedEx", tracking_number: "794644790132" },
    delivered_at: nil
  },
  {
    notification_type: "order_delivered",
    recipient: "dave@example.com",
    subject: "Order #R123456004 delivered",
    channel: "email",
    status: "delivered",
    payload: { order_number: "R123456004" },
    delivered_at: 4.hours.ago
  },
  {
    notification_type: "password_reset",
    recipient: "eve@example.com",
    subject: "Password reset requested",
    channel: "email",
    status: "delivered",
    payload: {},
    delivered_at: 6.hours.ago
  },
  {
    notification_type: "welcome",
    recipient: "dave@example.com",
    subject: "Welcome to our store!",
    channel: "email",
    status: "delivered",
    payload: { name: "Dave" },
    delivered_at: 2.days.ago
  },
  {
    notification_type: "order_placed",
    recipient: "eve@example.com",
    subject: "Order #R123456005 confirmed",
    channel: "email",
    status: "pending",
    payload: { order_number: "R123456005", total: "59.99", item_count: 2 },
    delivered_at: nil
  }
]

sample_notifications.each do |attrs|
  Notification.find_or_create_by!(
    notification_type: attrs[:notification_type],
    recipient: attrs[:recipient],
    subject: attrs[:subject]
  ) do |n|
    n.channel = attrs[:channel]
    n.status = attrs[:status]
    n.payload = attrs[:payload]
    n.delivered_at = attrs[:delivered_at]
  end
  puts "  Created notification: #{attrs[:notification_type]} → #{attrs[:recipient]}"
end

puts "Done creating sample notifications!"
