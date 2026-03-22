# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

Spree::Core::Engine.load_seed if defined?(Spree::Core)

puts "Setting up portrait studio demo data..."

require "open-uri"
require "digest"

store = Spree::Store.first
us = Spree::Country.find_by(iso: "US")
stock_location = Spree::StockLocation.first

# Update store branding
store.update!(name: "Portraiture Studio", url: "localhost:3000")

# Ensure payment methods exist (spree_sample normally creates these)
bogus_cc = Spree::PaymentMethod.find_or_create_by!(name: "Credit Card") do |pm|
  pm.type = "Spree::Gateway::Bogus"
  pm.description = "Bogus payment gateway for testing."
  pm.active = true
  pm.display_on = "both"
end
Spree::PaymentMethod.find_or_create_by!(name: "Check") do |pm|
  pm.type = "Spree::PaymentMethod::Check"
  pm.description = "Pay by check."
  pm.active = true
  pm.display_on = "back_end"
end

# ---------------------------------------------------------------------------
# Clean up clothing sample data (from spree_sample) on first run
# ---------------------------------------------------------------------------
if Spree::Taxon.exists?(name: "Men") || Spree::Taxon.exists?(name: "Women") || Spree::Taxon.exists?(name: "Sportswear")
  puts "  Removing clothing sample data..."
  Spree::Image.destroy_all
  Spree::LineItem.delete_all
  Spree::Payment.delete_all
  Spree::Shipment.delete_all
  Spree::ReturnAuthorization.delete_all
  Spree::Order.delete_all
  Spree::StockItem.delete_all
  Spree::Price.delete_all
  Spree::Variant.where(is_master: false).delete_all
  Spree::Classification.delete_all
  Spree::StoreProduct.delete_all
  Spree::Product.delete_all
  Spree::Variant.delete_all # master variants
  FriendlyId::Slug.where(sluggable_type: "Spree::Product").delete_all rescue nil
  FriendlyId::Slug.where(sluggable_type: "Spree::Taxon").delete_all rescue nil
  Spree::OptionValueVariant.delete_all
  Spree::OptionValue.delete_all
  Spree::OptionType.delete_all
  Spree::Taxon.where.not(parent_id: nil).order(depth: :desc).delete_all
  Spree::Taxon.delete_all
  Spree::Taxonomy.delete_all
  puts "  Cleaned."
end

# ---------------------------------------------------------------------------
# Taxonomies & Taxons (portrait categories)
# ---------------------------------------------------------------------------
puts "\nCreating portrait categories..."

categories_taxonomy = Spree::Taxonomy.find_or_create_by!(name: "Categories", store: store)
styles_taxonomy = Spree::Taxonomy.find_or_create_by!(name: "Styles", store: store)
collections_taxonomy = Spree::Taxonomy.find_or_create_by!(name: "Collections", store: store)

# Categories root taxon
cat_root = categories_taxonomy.root || Spree::Taxon.find_or_create_by!(name: "Categories", taxonomy: categories_taxonomy, parent: nil)

category_tree = {
  "Canvas Prints" => ["Gallery Wrapped", "Framed Canvas", "Canvas Rolls"],
  "Fine Art Prints" => ["Giclée Prints", "Matte Prints", "Glossy Prints"],
  "Photo Prints" => ["Standard Prints", "Large Format", "Panoramic"],
  "Wall Art" => ["Metal Prints", "Acrylic Prints", "Wood Prints"],
  "Miniatures" => ["Wallet Size", "Desk Prints", "Mini Canvas"]
}

category_tree.each do |parent_name, children|
  parent = Spree::Taxon.find_or_create_by!(name: parent_name, taxonomy: categories_taxonomy, parent: cat_root)
  children.each do |child_name|
    Spree::Taxon.find_or_create_by!(name: child_name, taxonomy: categories_taxonomy, parent: parent)
  end
end

# Styles
styles_root = styles_taxonomy.root || Spree::Taxon.find_or_create_by!(name: "Styles", taxonomy: styles_taxonomy, parent: nil)
%w[Classic Modern Vintage Minimalist Dramatic].each do |style|
  Spree::Taxon.find_or_create_by!(name: style, taxonomy: styles_taxonomy, parent: styles_root)
end

# Collections
col_root = collections_taxonomy.root || Spree::Taxon.find_or_create_by!(name: "Collections", taxonomy: collections_taxonomy, parent: nil)
["New Arrivals", "Bestsellers", "Artist Picks", "Limited Edition", "Seasonal"].each do |col|
  Spree::Taxon.find_or_create_by!(name: col, taxonomy: collections_taxonomy, parent: col_root)
end

puts "  Created #{Spree::Taxon.count} taxons"

# ---------------------------------------------------------------------------
# Option Types
# ---------------------------------------------------------------------------
puts "\nCreating option types..."

size_type = Spree::OptionType.find_or_create_by!(name: "print_size", presentation: "Print Size")
frame_type = Spree::OptionType.find_or_create_by!(name: "frame", presentation: "Frame")
finish_type = Spree::OptionType.find_or_create_by!(name: "finish", presentation: "Finish")

sizes = {
  '8x10' => '8" × 10"',
  '11x14' => '11" × 14"',
  '16x20' => '16" × 20"',
  '20x24' => '20" × 24"',
  '24x36' => '24" × 36"'
}

frames = {
  "no-frame" => "No Frame",
  "black" => "Black Frame",
  "white" => "White Frame",
  "walnut" => "Walnut Frame",
  "gold" => "Gold Frame"
}

finishes = {
  "matte" => "Matte",
  "glossy" => "Glossy",
  "satin" => "Satin"
}

sizes.each_with_index do |(name, pres), i|
  Spree::OptionValue.find_or_create_by!(name: name, option_type: size_type) { |v| v.presentation = pres; v.position = i }
end
frames.each_with_index do |(name, pres), i|
  Spree::OptionValue.find_or_create_by!(name: name, option_type: frame_type) { |v| v.presentation = pres; v.position = i }
end
finishes.each_with_index do |(name, pres), i|
  Spree::OptionValue.find_or_create_by!(name: name, option_type: finish_type) { |v| v.presentation = pres; v.position = i }
end

# ---------------------------------------------------------------------------
# Products — Portrait catalog
# ---------------------------------------------------------------------------
puts "\nCreating portrait products..."

default_shipping = Spree::ShippingCategory.find_or_create_by!(name: "Default")
tax_category = Spree::TaxCategory.first

# Product definitions: [name, base_price, description, category_taxon, style_taxon, collection_taxons]
portrait_products = [
  # Canvas Prints
  { name: "Golden Hour Portrait", price: 89.99, cat: "Gallery Wrapped", style: "Modern", col: ["Bestsellers"],
    desc: "A warm, sun-drenched portrait captured during golden hour with soft natural lighting and rich amber tones." },
  { name: "Studio Classic Headshot", price: 59.99, cat: "Gallery Wrapped", style: "Classic", col: ["Bestsellers"],
    desc: "Professional studio headshot with neutral backdrop, perfect lighting, and timeless composition." },
  { name: "Family Gathering Canvas", price: 149.99, cat: "Framed Canvas", style: "Classic", col: ["Bestsellers", "Artist Picks"],
    desc: "Multi-subject family portrait on premium canvas with museum-quality framing." },
  { name: "Moody Chiaroscuro Portrait", price: 129.99, cat: "Gallery Wrapped", style: "Dramatic", col: ["Artist Picks"],
    desc: "Dramatic portrait with deep shadows and rich highlights inspired by Renaissance chiaroscuro technique." },
  { name: "Child's First Portrait", price: 79.99, cat: "Framed Canvas", style: "Classic", col: ["New Arrivals"],
    desc: "Tender childhood portrait on archival canvas, capturing innocence and wonder." },
  { name: "Couple's Embrace", price: 119.99, cat: "Gallery Wrapped", style: "Modern", col: ["Bestsellers"],
    desc: "Intimate couple's portrait with soft focus background and natural warmth." },
  { name: "Vintage Film Portrait", price: 99.99, cat: "Canvas Rolls", style: "Vintage", col: ["Artist Picks"],
    desc: "Portrait with authentic film grain texture and muted color palette evoking classic photography." },

  # Fine Art Prints
  { name: "Ethereal Garden Portrait", price: 74.99, cat: "Giclée Prints", style: "Modern", col: ["New Arrivals"],
    desc: "Giclée fine art print of a dreamy outdoor portrait surrounded by lush botanical elements." },
  { name: "High-Key Beauty Portrait", price: 64.99, cat: "Matte Prints", style: "Minimalist", col: ["New Arrivals"],
    desc: "Bright, airy beauty portrait with soft high-key lighting on premium matte paper." },
  { name: "Graduation Portrait", price: 49.99, cat: "Glossy Prints", style: "Classic", col: ["Seasonal"],
    desc: "Celebratory graduation portrait with cap and gown, printed on vibrant glossy stock." },
  { name: "Environmental Portrait", price: 84.99, cat: "Giclée Prints", style: "Modern", col: ["Artist Picks"],
    desc: "Subject photographed in their natural environment — workshop, studio, or garden." },
  { name: "Noir Portrait Series", price: 109.99, cat: "Matte Prints", style: "Dramatic", col: ["Limited Edition"],
    desc: "High-contrast black and white portrait series on heavyweight matte paper." },
  { name: "Watercolor Effect Portrait", price: 94.99, cat: "Giclée Prints", style: "Vintage", col: ["Artist Picks"],
    desc: "Digital watercolor rendering of a portrait, printed as a museum-quality giclée." },
  { name: "Pet Portrait - Classic", price: 69.99, cat: "Matte Prints", style: "Classic", col: ["Bestsellers"],
    desc: "Dignified pet portrait in classic oil-painting style on archival matte paper." },

  # Photo Prints
  { name: "Newborn Announcement Print", price: 34.99, cat: "Standard Prints", style: "Minimalist", col: ["Seasonal"],
    desc: "Delicate newborn portrait, perfect for birth announcements and nursery décor." },
  { name: "Senior Year Portrait Pack", price: 44.99, cat: "Standard Prints", style: "Modern", col: ["Seasonal"],
    desc: "Set of senior portraits in multiple poses on premium photo paper." },
  { name: "Cityscape Self-Portrait", price: 79.99, cat: "Large Format", style: "Modern", col: ["New Arrivals"],
    desc: "Urban self-portrait set against a dramatic city skyline, printed in stunning large format." },
  { name: "Panoramic Family Beach Portrait", price: 119.99, cat: "Panoramic", style: "Classic", col: ["Seasonal"],
    desc: "Wide panoramic portrait of a family on the beach at sunset." },
  { name: "Executive Headshot Set", price: 54.99, cat: "Standard Prints", style: "Classic", col: ["Bestsellers"],
    desc: "Professional executive headshot set with multiple expressions for corporate use." },
  { name: "Maternity Portrait", price: 64.99, cat: "Standard Prints", style: "Modern", col: ["New Arrivals"],
    desc: "Beautiful maternity portrait celebrating the journey to parenthood." },
  { name: "Wedding Portrait Panoramic", price: 139.99, cat: "Panoramic", style: "Classic", col: ["Bestsellers"],
    desc: "Sweeping panoramic wedding portrait capturing the ceremony's grandeur." },

  # Wall Art
  { name: "Modern Portrait on Metal", price: 159.99, cat: "Metal Prints", style: "Modern", col: ["Limited Edition"],
    desc: "Vivid portrait infused directly onto brushed aluminum for a contemporary floating effect." },
  { name: "Acrylic Face Mount Portrait", price: 189.99, cat: "Acrylic Prints", style: "Dramatic", col: ["Limited Edition"],
    desc: "Gallery-quality portrait face-mounted on crystal-clear acrylic with polished edges." },
  { name: "Rustic Wood Portrait", price: 109.99, cat: "Wood Prints", style: "Vintage", col: ["Artist Picks"],
    desc: "Portrait printed on natural wood plank, with visible grain adding organic texture." },
  { name: "Abstract Portrait on Metal", price: 174.99, cat: "Metal Prints", style: "Modern", col: ["Limited Edition"],
    desc: "Artistically abstracted portrait on metal with vivid colors and sharp detail." },
  { name: "Retro Pop Art Portrait", price: 134.99, cat: "Acrylic Prints", style: "Vintage", col: ["Artist Picks"],
    desc: "Pop-art style portrait in bold primary colors, mounted on glossy acrylic." },
  { name: "Heritage Wood Portrait", price: 99.99, cat: "Wood Prints", style: "Classic", col: ["Bestsellers"],
    desc: "Timeless portrait on reclaimed wood, perfect for rustic and farmhouse décor." },

  # Miniatures
  { name: "Wallet Portrait Set (8)", price: 14.99, cat: "Wallet Size", style: "Classic", col: [],
    desc: "Set of eight wallet-size portraits, ideal for sharing with family and friends." },
  { name: "Desk Portrait with Easel", price: 29.99, cat: "Desk Prints", style: "Minimalist", col: ["New Arrivals"],
    desc: "Small desk portrait with built-in easel backing for office or bedside display." },
  { name: "Mini Canvas Portrait", price: 39.99, cat: "Mini Canvas", style: "Modern", col: [],
    desc: "Tiny gallery-wrapped canvas portrait, perfect for shelves and gallery walls." },
  { name: "Locket Portrait Print", price: 9.99, cat: "Wallet Size", style: "Vintage", col: [],
    desc: "Precision-cut miniature portrait sized to fit standard lockets and pendants." },
  { name: "Pet Portrait Mini Canvas", price: 34.99, cat: "Mini Canvas", style: "Classic", col: [],
    desc: "Adorable mini canvas portrait of your pet in classic painted style." },
]

portrait_products.each do |pdata|
  sleep(0.1) # avoid deadlocks on taxon counter cache

  product = Spree::Product.find_or_create_by!(name: pdata[:name]) do |p|
    p.price = pdata[:price]
    p.description = pdata[:desc]
    p.available_on = Time.zone.now
    p.status = "active"
    p.shipping_category = default_shipping
    p.tax_category = tax_category
    p.option_types = [size_type, frame_type, finish_type]
  end

  # Assign taxons
  cat_taxon = Spree::Taxon.find_by(name: pdata[:cat])
  style_taxon = Spree::Taxon.find_by(name: pdata[:style])
  col_taxons = pdata[:col].map { |c| Spree::Taxon.find_by(name: c) }.compact

  all_taxons = [cat_taxon, cat_taxon&.parent, style_taxon, *col_taxons].compact.uniq
  all_taxons.each do |taxon|
    retries = 0
    begin
      Spree::Classification.find_or_create_by!(product: product, taxon: taxon)
    rescue ActiveRecord::Deadlocked, ActiveRecord::RecordNotUnique
      retries += 1
      sleep 0.2
      retry if retries < 3
    end
  end

  # Ensure store association
  Spree::StoreProduct.find_or_create_by!(store: store, product: product)

  # Create variants (size × frame combinations, all finishes bundled)
  next if product.variants.where(is_master: false).any?

  size_values = Spree::OptionValue.where(option_type: size_type)
  frame_values = Spree::OptionValue.where(option_type: frame_type)
  default_finish = Spree::OptionValue.find_by(name: "matte", option_type: finish_type)

  # Price multipliers by size
  size_multipliers = { "8x10" => 1.0, "11x14" => 1.4, "16x20" => 1.8, "20x24" => 2.3, "24x36" => 3.0 }
  frame_adders = { "no-frame" => 0, "black" => 25, "white" => 25, "walnut" => 40, "gold" => 55 }

  size_values.each do |sv|
    frame_values.each do |fv|
      variant_price = (pdata[:price] * size_multipliers.fetch(sv.name, 1.0) + frame_adders.fetch(fv.name, 0)).round(2)
      sku = "#{product.id}-#{sv.name}-#{fv.name}"

      variant = product.variants.find_or_create_by!(sku: sku) do |v|
        v.option_values = [sv, fv, default_finish]
      end
      variant.prices.find_or_create_by!(currency: "USD") { |p| p.amount = variant_price }

      # Stock
      si = Spree::StockItem.find_or_create_by!(variant: variant, stock_location: stock_location)
      si.set_count_on_hand(rand(5..50)) if si.count_on_hand == 0
    end
  end

  # Stock for master variant too
  si = Spree::StockItem.find_or_create_by!(variant: product.master, stock_location: stock_location)
  si.set_count_on_hand(rand(10..100)) if si.count_on_hand == 0

  puts "  Created: #{pdata[:name]} ($#{pdata[:price]} base, #{product.variants.where(is_master: false).count} variants)"
end

# ---------------------------------------------------------------------------
# Product Images (placeholder from picsum.photos)
# ---------------------------------------------------------------------------
puts "\nAttaching product images..."

products_needing_images = Spree::Product.where(deleted_at: nil).select { |p| p.master.images.empty? }
total = products_needing_images.count
puts "  #{total} products need images"

products_needing_images.each_with_index do |product, idx|
  seed_id = Digest::MD5.hexdigest(product.name)[0..7]
  url = "https://picsum.photos/seed/#{seed_id}/600/600"

  begin
    file = URI.open(url, open_timeout: 10, read_timeout: 10)
    img = Spree::Image.new(viewable: product.master, alt: product.name, position: 1)
    img.attachment.attach(io: file, filename: "product_#{product.id}.jpg", content_type: "image/jpeg")
    img.save!
    print "\r  Attached #{idx + 1}/#{total}: #{product.name[0..40]}" + " " * 20
  rescue => e
    print "\r  Failed #{idx + 1}/#{total}: #{product.name[0..30]} (#{e.message[0..40]})" + " " * 10
  end
end
puts "\n  Done attaching images!" if total > 0

# ---------------------------------------------------------------------------
# Admin user
# ---------------------------------------------------------------------------
if defined?(Spree::AdminUser)
  Spree::AdminUser.find_or_create_by!(email: "admin@demo.com") do |u|
    u.password = "demo1234"
    u.password_confirmation = "demo1234"
    puts "  Created admin user: admin@demo.com / demo1234"
  end
end

# ---------------------------------------------------------------------------
# Customer accounts
# ---------------------------------------------------------------------------
puts "\nCreating customers..."

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
def create_demo_order(store:, user:, stock_location:, payment_method:, variants:, completed_days_ago: nil, shipped: false, returned: false, canceled: false)
  return if Spree::Order.where(email: user.email).count >= 3

  order = Spree::Order.create!(
    store: store, user: user, email: user.email,
    currency: store.default_currency,
    bill_address: user.bill_address || Spree::Address.first,
    ship_address: user.ship_address || Spree::Address.first,
    state: "cart",
    created_at: (completed_days_ago || 1).days.ago
  )

  variants.each do |vd|
    Spree::Cart::AddItem.call(order: order, variant: vd[:variant], quantity: vd[:quantity] || 1)
  end
  order.update_with_updater!

  order.update_columns(state: "complete", completed_at: (completed_days_ago || 1).days.ago,
                       payment_state: "paid", payment_total: order.total)

  payment = Spree::Payment.new(order: order, payment_method: payment_method, amount: order.total, state: "completed")
  payment.save!(validate: false)

  if order.shipments.empty? && stock_location
    sm = Spree::ShippingMethod.first
    shipment = order.shipments.create!(stock_location: stock_location, cost: [4.99, 7.99, 12.99].sample, state: "pending")
    shipment.shipping_rates.create!(shipping_method: sm, cost: shipment.cost, selected: true)
    order.line_items.each do |li|
      shipment.inventory_units.create!(variant: li.variant, order: order, line_item: li, state: "on_hand")
    end
  end

  if shipped
    order.shipments.each do |s|
      s.update_columns(state: "shipped", shipped_at: (completed_days_ago.to_i - 1).days.ago,
                       tracking: "1Z#{rand(100_000_000..999_999_999)}")
      s.inventory_units.update_all(state: "shipped")
    end
    order.update_columns(shipment_state: "shipped")
  else
    order.update_columns(shipment_state: "pending")
  end

  if returned && order.shipments.any? { |s| s.state == "shipped" }
    reason = Spree::ReturnAuthorizationReason.first
    if reason
      rma = order.return_authorizations.create!(
        number: "RA#{order.number.gsub('R', '')}",
        stock_location: stock_location,
        return_authorization_reason_id: reason.id,
        memo: ["Print arrived damaged", "Wrong size ordered", "Color doesn't match", "Changed my mind"].sample
      )
      order.update_columns(state: "awaiting_return")
      puts "    Created RMA: #{rma.number}"
    end
  end

  order.update_columns(state: "canceled", canceled_at: (completed_days_ago.to_i - 1).days.ago) if canceled

  puts "  Created order: #{order.number} (#{order.state}, $#{order.total}, #{order.line_items.count} items)"
  order
end

# ---------------------------------------------------------------------------
# Demo orders
# ---------------------------------------------------------------------------
puts "\nCreating demo orders..."

users = Spree::User.where(email: %w[alice@example.com bob@example.com carol@example.com dave@example.com eve@example.com])
                    .index_by(&:email)

all_variants = Spree::Variant.joins(:product).where(is_master: false, spree_products: { deleted_at: nil })
                              .limit(50).to_a.select { |v| v.price.present? && v.price > 0 }

if all_variants.any? && users.any? && store && stock_location && bogus_cc
  # Shipped orders
  %w[alice@example.com bob@example.com carol@example.com dave@example.com].each_with_index do |email, i|
    create_demo_order(
      store: store, user: users[email], stock_location: stock_location, payment_method: bogus_cc,
      variants: all_variants.sample(rand(1..3)).map { |v| { variant: v, quantity: 1 } },
      completed_days_ago: 14 - i * 3, shipped: true
    )
  end

  # Pending orders
  %w[eve@example.com alice@example.com].each_with_index do |email, i|
    create_demo_order(
      store: store, user: users[email], stock_location: stock_location, payment_method: bogus_cc,
      variants: all_variants.sample(rand(1..2)).map { |v| { variant: v, quantity: 1 } },
      completed_days_ago: 1 + i, shipped: false
    )
  end

  # Returns
  create_demo_order(
    store: store, user: users["bob@example.com"], stock_location: stock_location, payment_method: bogus_cc,
    variants: all_variants.sample(2).map { |v| { variant: v, quantity: 1 } },
    completed_days_ago: 30, shipped: true, returned: true
  )

  # Canceled
  create_demo_order(
    store: store, user: users["dave@example.com"], stock_location: stock_location, payment_method: bogus_cc,
    variants: all_variants.sample(1).map { |v| { variant: v, quantity: 1 } },
    completed_days_ago: 5, shipped: false, canceled: true
  )
end

# ---------------------------------------------------------------------------
# Price Lists
# ---------------------------------------------------------------------------
puts "\nCreating price lists..."

[
  { name: "Default Retail", description: "Standard retail pricing", match_policy: "all" },
  { name: "VIP Collectors", description: "15% discount for repeat collectors", match_policy: "any" },
  { name: "Wholesale / Galleries", description: "Gallery bulk pricing for 10+ prints", match_policy: "any" },
  { name: "Holiday Portrait Sale", description: "Seasonal holiday promotion", match_policy: "all",
    starts_at: Date.new(2026, 11, 20), ends_at: Date.new(2026, 12, 31) },
  { name: "Artist Studio Discount", description: "Internal studio pricing", match_policy: "any" }
].each do |pl|
  Spree::PriceList.find_or_create_by!(name: pl[:name], store: store) do |price_list|
    price_list.description = pl[:description]
    price_list.match_policy = pl[:match_policy]
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
  { code: "PORTRAIT-25", amount: 25.00, user_email: "alice@example.com", amount_used: 12.50, final_state: "partially_redeemed" },
  { code: "PORTRAIT-50", amount: 50.00, user_email: "bob@example.com", amount_used: 0 },
  { code: "STUDIO-100", amount: 100.00, user_email: nil, amount_used: 0 },
  { code: "PORTRAIT-75", amount: 75.00, user_email: "carol@example.com", amount_used: 75.00,
    redeemed_at: 5.days.ago, final_state: "redeemed" },
  { code: "STUDIO-200", amount: 200.00, user_email: "dave@example.com", amount_used: 45.00, final_state: "partially_redeemed" },
  { code: "PORTRAIT-500-VIP", amount: 500.00, user_email: nil, amount_used: 0, expires_at: 6.months.from_now }
].each do |gc_data|
  user = gc_data[:user_email] ? Spree::User.find_by(email: gc_data[:user_email]) : nil
  gc = Spree::GiftCard.find_or_create_by!(code: gc_data[:code].downcase) do |gift_card|
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
  { user_email: "alice@example.com", amount: 15.00, memo: "Refund for damaged print in transit" },
  { user_email: "bob@example.com", amount: 50.00, memo: "Loyalty reward - 1 year collector" },
  { user_email: "carol@example.com", amount: 25.00, memo: "Compensation for late delivery" },
  { user_email: "dave@example.com", amount: 100.00, memo: "Return credit for wrong size order" },
  { user_email: "eve@example.com", amount: 10.00, memo: "Welcome bonus credit" }
].each do |sc_data|
  user = Spree::User.find_by(email: sc_data[:user_email])
  next unless user
  next if Spree::StoreCredit.exists?(user: user, memo: sc_data[:memo])

  Spree::StoreCredit.create!(
    user: user, amount: sc_data[:amount], currency: "USD",
    category: category, store: store, created_by_id: admin&.id || 1, memo: sc_data[:memo]
  )
  puts "  Created store credit: $#{sc_data[:amount]} for #{sc_data[:user_email]}"
end

puts "\nDone! Portraiture Studio is ready."
