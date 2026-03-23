require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "notification-service")

  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    "deployment.environment" => ENV.fetch("RAILS_ENV", "development"),
    "service.version" => ENV.fetch("APP_VERSION", "0.1.0")
  )

  c.use "OpenTelemetry::Instrumentation::Rails"
  c.use "OpenTelemetry::Instrumentation::Rack"
  c.use "OpenTelemetry::Instrumentation::PG", db_statement: :obfuscate
  c.use "OpenTelemetry::Instrumentation::ActiveRecord"
end
