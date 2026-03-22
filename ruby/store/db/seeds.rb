# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Spree::Core::Engine.load_seed if defined?(Spree::Core)

# Additional seed data for demo purposes
puts "Creating additional demo data..."

store = Spree::Store.first
us = Spree::Country.find_by(iso: "US")
stock_location = Spree::StockLocation.first
bogus_cc = Spree::PaymentMethod.find_by(name: "Credit Card")

# Create extra admin user
if defined?(Spree::AdminUser)
  Spree::AdminUser.find_or_create_by!(email: "admin@demo.com") do |u|
    u.password = "demo1234"
    u.password_confirmation = "demo1234"
    puts "  Created admin user: admin@demo.com / demo1234"
  end
end

# Create customer accounts with addresses
if defined?(Spree::User)
  demo_customers = [
    { email: "alice@example.com", first_name: "Alice", last_name: "Johnson",
      address: { address1: "123 Main St", city: "New York", state: "NY", zipcode: "10001", phone: "212-555-0101" } },
    { email: "bob@example.com", first_name: "Bob", last_name: "Smith",
      address: { address1: "456 Oak Ave", city: "Los Angeles", state: "CA", zipcode: "90001", phone: "310-555-0102" } },
    { email: "carol@example.com", first_name: "Carol", last_name: "Williams",
      address: { address1: "789 Pine Rd", city: "Chicago", state: "IL", zipcode: "60601", phone: "312-555-0103" } },
    { email: "dave@example.com", first_name: "Dave", last_name: "Brown",
      address: { address1: "321 Elm St", city: "Houston", state: "TX", zipcode: "77001", phone: "713-555-0104" } },
    { email: "eve@example.com", first_name: "Eve", last_name: "Davis",
      address: { address1: "654 Cedar Ln", city: "Seattle", state: "WA", zipcode: "98101", phone: "206-555-0105" } }
  ]

  demo_customers.each do |customer|
    user = Spree::User.find_or_create_by!(email: customer[:email]) do |u|
      u.password = "password123"
      u.password_confirmation = "password123"
    end

    state = Spree::State.find_by(abbr: customer[:address][:state], country: us)
    addr = customer[:address].merge(
      firstname: customer[:first_name],
      lastname: customer[:last_name],
      country: us,
      state: state
    )

    user.update(bill_address: Spree::Address.find_or_create_by!(addr))
    user.update(ship_address: user.bill_address)

    puts "  Created customer: #{customer[:email]}"
  end
end

# ---------------------------------------------------------------------------
# Helper to build a complete order
# ---------------------------------------------------------------------------
def create_demo_order(store:, user:, stock_location:, payment_method:, variants:, state:, completed_days_ago: nil, shipped: false, returned: false, canceled: false)
  return if Spree::Order.exists?(email: user.email, state: state == :canceled ? ["complete", "canceled"] : state.to_s) &&
            Spree::Order.where(email: user.email).count >= 2

  order = Spree::Order.create!(
    store: store,
    user: user,
    email: user.email,
    currency: store.default_currency,
    bill_address: user.bill_address || Spree::Address.first,
    ship_address: user.ship_address || Spree::Address.first,
    state: "cart",
    created_at: (completed_days_ago || 1).days.ago
  )

  variants.each do |variant_data|
    variant = variant_data[:variant]
    qty = variant_data[:quantity] || 1
    Spree::Cart::AddItem.call(order: order, variant: variant, quantity: qty)
  end

  order.update_with_updater!

  # Progress to complete
  order.update_columns(state: "complete", completed_at: (completed_days_ago || 1).days.ago)
  order.update_columns(payment_state: "paid", payment_total: order.total)

  # Create payment record directly (bypassing source validation for demo data)
  payment = Spree::Payment.new(
    order: order,
    payment_method: payment_method,
    amount: order.total,
    state: "completed"
  )
  payment.save!(validate: false)

  # Create shipment if not already present
  if order.shipments.empty? && stock_location
    shipping_method = Spree::ShippingMethod.find_by(name: "UPS Ground (USD)") || Spree::ShippingMethod.first
    shipment = order.shipments.create!(
      stock_location: stock_location,
      cost: [4.99, 7.99, 12.99].sample,
      state: "pending"
    )
    shipment.shipping_rates.create!(
      shipping_method: shipping_method,
      cost: shipment.cost,
      selected: true
    )
    order.line_items.each do |li|
      shipment.inventory_units.create!(
        variant: li.variant,
        order: order,
        line_item: li,
        state: "on_hand"
      )
    end
  end

  if shipped
    order.shipments.each do |s|
      s.update_columns(state: "shipped", shipped_at: (completed_days_ago ? completed_days_ago - 1 : 0).days.ago,
                       tracking: "1Z#{rand(100_000_000..999_999_999)}")
      s.inventory_units.update_all(state: "shipped")
    end
    order.update_columns(shipment_state: "shipped")
  else
    order.update_columns(shipment_state: "pending")
  end

  if returned && order.shipments.any?(&:shipped?)
    reason = Spree::ReturnAuthorizationReason.first
    if reason
      rma = order.return_authorizations.create!(
        number: "RA#{order.number.gsub('R', '')}",
        stock_location: stock_location,
        return_authorization_reason_id: reason.id,
        memo: ["Item arrived damaged", "Wrong size", "Changed my mind", "Defective product"].sample
      )
      order.inventory_units.where(state: "shipped").limit(1).each do |iu|
        rma.return_items.create!(
          inventory_unit: iu,
          amount: iu.line_item.price,
          acceptance_status: "accepted"
        ) rescue nil
      end
      order.update_columns(state: "awaiting_return")
      puts "    Created RMA: #{rma.number}"
    end
  end

  if canceled
    order.update_columns(state: "canceled", canceled_at: (completed_days_ago ? completed_days_ago - 1 : 0).days.ago)
  end

  puts "  Created order: #{order.number} (#{order.state}, $#{order.total}, #{order.line_items.count} items)"
  order
end

# ---------------------------------------------------------------------------
# Build demo orders
# ---------------------------------------------------------------------------
puts "\nCreating demo orders..."

users = Spree::User.where(email: %w[alice@example.com bob@example.com carol@example.com dave@example.com eve@example.com])
                    .index_by(&:email)

all_variants = Spree::Variant.joins(:product)
                              .where(is_master: false)
                              .where(spree_products: { deleted_at: nil })
                              .limit(50)
                              .to_a
                              .select { |v| v.price.present? && v.price > 0 }

if all_variants.any? && users.any? && store && stock_location && bogus_cc
  # Fulfilled/shipped orders
  create_demo_order(
    store: store, user: users["alice@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(3).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 14, shipped: true
  )

  create_demo_order(
    store: store, user: users["bob@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(2).map { |v| { variant: v, quantity: rand(1..3) } },
    state: :complete, completed_days_ago: 10, shipped: true
  )

  create_demo_order(
    store: store, user: users["carol@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(5).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 7, shipped: true
  )

  create_demo_order(
    store: store, user: users["dave@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(1).map { |v| { variant: v, quantity: 2 } },
    state: :complete, completed_days_ago: 21, shipped: true
  )

  # Pending orders (paid but not shipped)
  create_demo_order(
    store: store, user: users["eve@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(2).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 1, shipped: false
  )

  create_demo_order(
    store: store, user: users["alice@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(4).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 2, shipped: false
  )

  # Returns
  create_demo_order(
    store: store, user: users["bob@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(2).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 30, shipped: true, returned: true
  )

  create_demo_order(
    store: store, user: users["carol@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(1).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 20, shipped: true, returned: true
  )

  # Canceled order
  create_demo_order(
    store: store, user: users["dave@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(3).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 5, shipped: false, canceled: true
  )

  create_demo_order(
    store: store, user: users["eve@example.com"], stock_location: stock_location,
    payment_method: bogus_cc,
    variants: all_variants.sample(1).map { |v| { variant: v, quantity: 1 } },
    state: :complete, completed_days_ago: 3, shipped: false, canceled: true
  )
else
  puts "  Skipping orders — missing variants, users, store, or payment method. Run spree_sample:load first."
end

# ---------------------------------------------------------------------------
# Price Lists
# ---------------------------------------------------------------------------
puts "\nCreating price lists..."

[
  { name: "Default Retail", description: "Standard retail pricing for all customers", match_policy: "all" },
  { name: "VIP Members", description: "10% discount for VIP loyalty members", match_policy: "any" },
  { name: "Wholesale", description: "Bulk pricing for wholesale partners (50+ units)", match_policy: "any" },
  { name: "Holiday Sale 2026", description: "Seasonal holiday promotion pricing", match_policy: "all",
    starts_at: Date.new(2026, 11, 20), ends_at: Date.new(2026, 12, 31) },
  { name: "Employee Discount", description: "25% discount for internal employees", match_policy: "any" },
  { name: "Flash Sale - Spring", description: "48-hour spring flash sale", match_policy: "all",
    starts_at: 30.days.ago, ends_at: 28.days.ago }
].each do |pl|
  Spree::PriceList.find_or_create_by!(name: pl[:name], store: store) do |price_list|
    price_list.description = pl[:description]
    price_list.match_policy = pl[:match_policy] if pl[:match_policy]
    price_list.starts_at = pl[:starts_at] if pl[:starts_at]
    price_list.ends_at = pl[:ends_at] if pl[:ends_at]
  end
  puts "  Created price list: #{pl[:name]}"
end

# ---------------------------------------------------------------------------
# Gift Cards
# ---------------------------------------------------------------------------
puts "\nCreating gift cards..."

admin = Spree::AdminUser.first

[
  { code: "GIFT-25-ALICE", amount: 25.00, user_email: "alice@example.com", amount_used: 12.50, final_state: "partially_redeemed" },
  { code: "GIFT-50-BOB", amount: 50.00, user_email: "bob@example.com", amount_used: 0 },
  { code: "GIFT-100-PROMO", amount: 100.00, user_email: nil, amount_used: 0 },
  { code: "GIFT-75-CAROL", amount: 75.00, user_email: "carol@example.com", amount_used: 75.00,
    redeemed_at: 5.days.ago, final_state: "redeemed" },
  { code: "GIFT-30-EXPIRED", amount: 30.00, user_email: nil, amount_used: 0,
    expires_at: 7.days.ago, final_state: "canceled" },
  { code: "GIFT-200-DAVE", amount: 200.00, user_email: "dave@example.com", amount_used: 45.00, final_state: "partially_redeemed" },
  { code: "GIFT-15-EVE", amount: 15.00, user_email: "eve@example.com", amount_used: 15.00, final_state: "redeemed" },
  { code: "GIFT-500-VIP", amount: 500.00, user_email: nil, amount_used: 0,
    expires_at: 6.months.from_now }
].each do |gc_data|
  user = gc_data[:user_email] ? Spree::User.find_by(email: gc_data[:user_email]) : nil
  gc = Spree::GiftCard.find_or_create_by!(code: gc_data[:code]) do |gift_card|
    gift_card.amount = gc_data[:amount]
    gift_card.currency = "USD"
    gift_card.store = store
    gift_card.user = user
    gift_card.created_by_id = admin&.id
    gift_card.expires_at = gc_data[:expires_at] if gc_data[:expires_at]
  end
  updates = { amount_used: gc_data[:amount_used] }
  updates[:state] = gc_data[:final_state] if gc_data[:final_state]
  updates[:redeemed_at] = gc_data[:redeemed_at] if gc_data[:redeemed_at]
  gc.update_columns(updates)
  puts "  Created gift card: #{gc_data[:code]} ($#{gc_data[:amount]}, #{gc.reload.state})"
end

# ---------------------------------------------------------------------------
# Store Credits
# ---------------------------------------------------------------------------
puts "\nCreating store credits..."

category = Spree::StoreCreditCategory.find_or_create_by!(name: "Default")

[
  { user_email: "alice@example.com", amount: 15.00, memo: "Refund for damaged item in order R123" },
  { user_email: "bob@example.com", amount: 50.00, memo: "Loyalty reward - 1 year anniversary" },
  { user_email: "carol@example.com", amount: 25.00, memo: "Compensation for late delivery" },
  { user_email: "dave@example.com", amount: 100.00, memo: "Return credit for order RA987654321" },
  { user_email: "eve@example.com", amount: 10.00, memo: "Welcome bonus credit" }
].each do |sc_data|
  user = Spree::User.find_by(email: sc_data[:user_email])
  next unless user

  existing = Spree::StoreCredit.find_by(user: user, memo: sc_data[:memo])
  next if existing

  Spree::StoreCredit.create!(
    user: user,
    amount: sc_data[:amount],
    currency: "USD",
    category: category,
    store: store,
    created_by_id: admin&.id || 1,
    memo: sc_data[:memo]
  )
  puts "  Created store credit: $#{sc_data[:amount]} for #{sc_data[:user_email]}"
end

puts "\nDone creating additional demo data!"
