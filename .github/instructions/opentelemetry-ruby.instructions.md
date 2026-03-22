---
description: 'OpenTelemetry instrumentation conventions for Ruby on Rails applications'
applyTo: '**/*.rb'
---

# OpenTelemetry Ruby Instrumentation

## Gems & Dependencies

### Core Gems (required in every service Gemfile)
```ruby
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"
```

### Targeted Instrumentation (when `instrumentation-all` is too broad)
Pick only the gems that match your service's stack:
```ruby
gem "opentelemetry-instrumentation-rails"
gem "opentelemetry-instrumentation-rack"
gem "opentelemetry-instrumentation-action_pack"
gem "opentelemetry-instrumentation-action_view"
gem "opentelemetry-instrumentation-active_record"
gem "opentelemetry-instrumentation-active_job"
gem "opentelemetry-instrumentation-active_support"
gem "opentelemetry-instrumentation-pg"
gem "opentelemetry-instrumentation-net_http"
gem "opentelemetry-instrumentation-faraday"
gem "opentelemetry-instrumentation-concurrent_ruby"
```

## SDK Configuration

### Initializer Pattern
Create `config/initializers/opentelemetry.rb`:
```ruby
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "my-service")
  c.service_version = ENV.fetch("OTEL_SERVICE_VERSION", "0.1.0")
  c.use_all
end
```

### Environment-Based Configuration (preferred)
Use standard OTel environment variables instead of hardcoding values:
- `OTEL_SERVICE_NAME` — logical service name
- `OTEL_SERVICE_VERSION` — service version
- `OTEL_EXPORTER_OTLP_ENDPOINT` — collector endpoint (default: `http://localhost:4318`)
- `OTEL_EXPORTER_OTLP_PROTOCOL` — `grpc` or `http/protobuf` (default: `http/protobuf`)
- `OTEL_RESOURCE_ATTRIBUTES` — comma-separated `key=value` resource attributes
- `OTEL_TRACES_SAMPLER` — sampler type (e.g., `parentbased_traceidratio`)
- `OTEL_TRACES_SAMPLER_ARG` — sampler argument (e.g., `0.5` for 50%)
- `OTEL_LOG_LEVEL` — SDK log level (`debug`, `info`, `warn`, `error`)

### Docker Compose Environment Variables
When running in Docker Compose, add these environment variables to each service:
```yaml
environment:
  OTEL_SERVICE_NAME: "store"
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://otel-collector:4318"
```

## Custom Spans

### Acquiring a Tracer
```ruby
tracer = OpenTelemetry.tracer_provider.tracer("my-service")
```

Or define a module-level constant for reuse:
```ruby
module MyService
  TRACER = OpenTelemetry.tracer_provider.tracer("my-service")
end
```

### Creating Spans
Use `in_span` for automatic span lifecycle management:
```ruby
tracer.in_span("process order", attributes: {
  "order.id" => order_id,
  "customer.id" => customer_id
}) do |span|
  # business logic here
  span.set_attribute("order.total", total)
end
```

### Recording Errors
```ruby
tracer.in_span("risky operation") do |span|
  begin
    do_work
  rescue => e
    span.record_exception(e)
    span.status = OpenTelemetry::Trace::Status.error(e.message)
    raise
  end
end
```

### Adding Events
```ruby
span.add_event("cache.miss", attributes: { "cache.key" => key })
```

## Span Naming Conventions

- Use `{verb} {object}` format: `calculate rates`, `fetch recommendations`, `send notification`
- Keep names low-cardinality — never include IDs or dynamic values in span names
- Place dynamic identifiers in span attributes instead
- Match the domain language of the service

## Attribute Conventions

### Follow OpenTelemetry Semantic Conventions
Use standard attribute names from the [OTel Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/) when they apply:

| Domain    | Attribute                   | Example            |
|-----------|-----------------------------|--------------------|
| HTTP      | `http.request.method`       | `"POST"`           |
| HTTP      | `url.full`                  | `"http://..."`     |
| HTTP      | `http.response.status_code` | `200`              |
| DB        | `db.system`                 | `"postgresql"`     |
| DB        | `db.name`                   | `"store_prod"`     |
| Messaging | `messaging.system`          | `"rabbitmq"`       |
| RPC       | `rpc.system`                | `"grpc"`           |

### Custom Attributes
- Prefix with the business domain: `order.id`, `shipping.carrier`, `notification.type`
- Use correct types: strings for IDs, integers for counts, floats for monetary values, booleans for flags
- Set attributes in bulk with a hash for efficiency:
  ```ruby
  span.add_attributes({
    "order.id" => order_id,
    "order.total" => 99.99,
    "order.item_count" => 3
  })
  ```
- Avoid high-cardinality attribute **keys** (never generate keys dynamically)

## Context Propagation

### Automatic (HTTP)
Auto-instrumentation for Faraday, Net::HTTP, and Rack automatically propagates W3C `traceparent`/`tracestate` headers. No manual work needed.

### Manual Propagation
When passing context outside of auto-instrumented libraries:
```ruby
# Inject into a carrier (e.g., headers hash)
headers = {}
OpenTelemetry.propagation.inject(headers)

# Extract from a carrier
context = OpenTelemetry.propagation.extract(headers)
OpenTelemetry::Context.with_current(context) do
  # spans created here are linked to the propagated trace
end
```

## Instrumentation in Service Objects

Wrap key business logic with spans:
```ruby
class ShippingRateCalculator
  TRACER = OpenTelemetry.tracer_provider.tracer("shipping-service")

  def self.calculate(origin:, destination:, package:)
    TRACER.in_span("calculate rates", attributes: {
      "shipping.origin.zip" => origin[:zip],
      "shipping.destination.zip" => destination[:zip],
      "shipping.package.weight" => package[:weight].to_f
    }) do |span|
      rates = compute_all_rates(origin, destination, package)
      span.set_attribute("shipping.rates.count", rates.size)
      rates
    end
  end
end
```

## Instrumentation in HTTP Clients

Faraday auto-instrumentation handles this, but for custom context:
```ruby
class ShippingClient
  TRACER = OpenTelemetry.tracer_provider.tracer("store")

  def calculate_rates(origin:, destination:, package:)
    TRACER.in_span("ShippingClient.calculate_rates", kind: :client, attributes: {
      "peer.service" => "shipping-service"
    }) do |span|
      response = @connection.post("/api/v1/rates") { |req| req.body = payload }
      span.set_attribute("http.response.status_code", response.status)
      response.body
    end
  end
end
```

## OTel Collector

### Docker Compose Service
```yaml
otel-collector:
  image: otel/opentelemetry-collector-contrib:latest
  command: ["--config=/etc/otel-collector-config.yaml"]
  volumes:
    - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
  ports:
    - "4317:4317"   # OTLP gRPC
    - "4318:4318"   # OTLP HTTP
    - "13133:13133" # Health check
```

### Minimal Collector Config (`otel-collector-config.yaml`)
```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:

exporters:
  debug:
    verbosity: detailed
  otlp:
    endpoint: jaeger:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp, debug]
```

## Testing with OpenTelemetry

Use the SDK test helpers to assert on spans in tests:
```ruby
require "opentelemetry/sdk"

# In test setup, use an in-memory exporter
ENV["OTEL_TRACES_EXPORTER"] = "none"

exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
  )
end

# After running code under test
spans = exporter.finished_spans
assert spans.any? { |s| s.name == "calculate rates" }
```

## Anti-Patterns to Avoid

- **Don't wrap every method in a span** — instrument meaningful operations, not implementation details
- **Don't put secrets or PII in attributes** — sanitize sensitive data
- **Don't use high-cardinality span names** — no user IDs, request IDs, or UUIDs in span names
- **Don't swallow exceptions silently** — use `span.record_exception` before re-raising
- **Don't create tracers in hot loops** — acquire tracer once and reuse it
- **Don't hardcode exporter endpoints** — use `OTEL_EXPORTER_OTLP_ENDPOINT` env var
- **Don't forget to set `span.status` on error** — status defaults to `UNSET`
