# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "shipping-service")

  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    "deployment.environment" => ENV.fetch("RAILS_ENV", "development"),
    "service.version" => ENV.fetch("APP_VERSION", "0.1.0")
  )

  c.use_all("OpenTelemetry::Instrumentation::PG" => { db_statement: :obfuscate })
end
