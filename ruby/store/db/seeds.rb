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

# Create extra admin user
if defined?(Spree::AdminUser)
  Spree::AdminUser.find_or_create_by!(email: "admin@demo.com") do |u|
    u.password = "demo1234"
    u.password_confirmation = "demo1234"
    puts "  Created admin user: admin@demo.com / demo1234"
  end
end

# Create extra customer accounts
if defined?(Spree::User)
  demo_customers = [
    { email: "alice@example.com", first_name: "Alice", last_name: "Johnson" },
    { email: "bob@example.com", first_name: "Bob", last_name: "Smith" },
    { email: "carol@example.com", first_name: "Carol", last_name: "Williams" },
    { email: "dave@example.com", first_name: "Dave", last_name: "Brown" },
    { email: "eve@example.com", first_name: "Eve", last_name: "Davis" }
  ]

  demo_customers.each do |customer|
    user = Spree::User.find_or_create_by!(email: customer[:email]) do |u|
      u.password = "password123"
      u.password_confirmation = "password123"
    end
    puts "  Created customer: #{customer[:email]}"
  end
end

puts "Done creating additional demo data!"
