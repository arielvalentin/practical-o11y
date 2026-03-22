# Service URLs for inter-service communication
Rails.application.config.x.services = ActiveSupport::OrderedOptions.new
Rails.application.config.x.services.shipping_url = ENV.fetch("SHIPPING_SERVICE_URL", "http://localhost:3001")
Rails.application.config.x.services.recommendation_url = ENV.fetch("RECOMMENDATION_SERVICE_URL", "http://localhost:3002")
Rails.application.config.x.services.notification_url = ENV.fetch("NOTIFICATION_SERVICE_URL", "http://localhost:3003")
