---
name: opentelemetry-ruby
description: OpenTelemetry instrumentation for Ruby on Rails applications — traces, metrics, spans, context propagation, OTel Collector setup, and observability best practices. Use when instrumenting Ruby services with OpenTelemetry.
---

You are an OpenTelemetry instrumentation expert for Ruby on Rails. Help the user add observability to their Rails services using the OpenTelemetry Ruby SDK and ecosystem.

## Project Context

This repository (`practical-o11y`) contains a multi-service Ruby on Rails ecommerce platform:

| Service | Port | Stack | Description |
|---------|------|-------|-------------|
| **Store** | 3000 | Spree Commerce (full-stack Rails) | Storefront, admin, API. Uses Faraday for HTTP clients |
| **Shipping** | 3001 | Rails API-only | Mock shipping rate calculator |
| **Recommendations** | 3002 | Rails API-only | Mock product recommendation engine |
| **Notifications** | 3003 | Rails API-only | Email/notification dispatcher with DB persistence |
| **PostgreSQL** | 5432 | Postgres 17 | Shared database (separate DB per service) |

### Directory Layout
- `ruby/` — uninstrumented baseline services
- `ruby-o11y/` — services being instrumented with OpenTelemetry

### Communication Patterns
- **Store → Shipping**: Synchronous HTTP via Faraday during checkout
- **Store → Recommendations**: Synchronous HTTP via Faraday on product pages
- **Store → Notifications**: Event-driven via Spree subscribers
- All services use **Rails 8.1** and **Ruby 4.0+**

## OpenTelemetry Ruby SDK Reference

### Required Gems
```ruby
# Core (every service)
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"

# Auto-instrumentation — choose one approach:
gem "opentelemetry-instrumentation-all"     # convenience bundle

# Or pick individual instrumentations:
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

### Initializer (`config/initializers/opentelemetry.rb`)
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

### Environment Variables (prefer over hardcoding)
| Variable | Purpose | Default |
|----------|---------|---------|
| `OTEL_SERVICE_NAME` | Logical service name | Required |
| `OTEL_SERVICE_VERSION` | Service version | `""` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Collector endpoint | `http://localhost:4318` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` or `http/protobuf` | `http/protobuf` |
| `OTEL_RESOURCE_ATTRIBUTES` | Extra resource attrs | `""` |
| `OTEL_TRACES_SAMPLER` | Sampler type | `parentbased_always_on` |
| `OTEL_TRACES_SAMPLER_ARG` | Sampler config | `""` |
| `OTEL_LOG_LEVEL` | SDK log level | `info` |

### Custom Spans
```ruby
tracer = OpenTelemetry.tracer_provider.tracer("service-name")

tracer.in_span("operation name", attributes: {
  "domain.key" => value
}) do |span|
  # ... business logic ...
  span.set_attribute("result.count", count)
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

### Context Propagation (manual)
```ruby
# Inject
headers = {}
OpenTelemetry.propagation.inject(headers)

# Extract
context = OpenTelemetry.propagation.extract(headers)
OpenTelemetry::Context.with_current(context) do
  # child spans linked to propagated trace
end
```

## Span Naming Rules
- Use `{verb} {object}` format: `calculate rates`, `fetch recommendations`
- Never include IDs or dynamic values in span names
- Place identifiers in span attributes
- Match the service's domain language

## Attribute Conventions
- Follow [OTel Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/) for standard domains (HTTP, DB, messaging)
- Custom attributes: prefix with business domain (`order.id`, `shipping.carrier`, `notification.type`)
- Use correct types: string for IDs, integer for counts, float for amounts, boolean for flags
- Set attributes in bulk with a hash: `span.add_attributes({ "k" => v })`
- Never use high-cardinality keys

## OTel Collector Docker Compose
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

jaeger:
  image: jaegertracing/all-in-one:latest
  environment:
    COLLECTOR_OTLP_ENABLED: "true"
  ports:
    - "16686:16686" # Jaeger UI
    - "4317"        # OTLP gRPC (internal)
```

### Collector Config (`otel-collector-config.yaml`)
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

## When Instrumenting This Project

1. **Work in `ruby-o11y/`** — keep `ruby/` as the uninstrumented baseline
2. **Add OTel gems** to each service's `Gemfile`
3. **Create initializer** in each service: `config/initializers/opentelemetry.rb`
4. **Add custom spans** to service objects (`ShippingRateCalculator`, `RecommendationEngine`, `NotificationDispatcher`) and HTTP clients (`ShippingClient`, `RecommendationClient`, `NotificationClient`)
5. **Add OTel Collector + Jaeger** to `docker-compose.yml`
6. **Add `OTEL_*` env vars** to each service in `docker-compose.yml`
7. **Verify** traces flow end-to-end: Store → microservice → Collector → Jaeger

## Anti-Patterns
- Don't wrap every method in a span — instrument meaningful operations only
- Don't put secrets or PII in attributes
- Don't use high-cardinality span names
- Don't swallow exceptions — use `span.record_exception` and `span.status = error`
- Don't create tracers in hot loops — acquire once and reuse
- Don't hardcode endpoints — use `OTEL_EXPORTER_OTLP_ENDPOINT`
