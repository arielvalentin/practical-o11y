---
name: otel-ruby
description: OpenTelemetry instrumentation for Ruby and Rails applications — SDK setup, auto and manual instrumentation, context propagation, exporters, collector configuration, and observability best practices.
---

# OpenTelemetry Ruby Instrumentation Guide

Comprehensive reference for instrumenting Ruby and Ruby on Rails applications with OpenTelemetry. Covers tracing, metrics, and logs across single services and distributed microservice architectures.

## Gems

### Core SDK

```ruby
# Gemfile
gem "opentelemetry-sdk", "~> 1.10"
gem "opentelemetry-exporter-otlp", "~> 0.31"
```

- `opentelemetry-sdk` — Core tracing API, span processors, resource management
- `opentelemetry-exporter-otlp` — Exports telemetry over OTLP (HTTP or gRPC) to any compatible backend or collector

### Auto-Instrumentation (All-in-One)

```ruby
# Gemfile — pulls in all available instrumentation gems
gem "opentelemetry-instrumentation-all", "~> 0.74"
```

Use this for quick setup. For production, prefer selecting only the instrumentations you need.

### Individual Instrumentation Gems

Pick only what your application uses:

```ruby
# Gemfile — web frameworks & middleware
gem "opentelemetry-instrumentation-rails"
gem "opentelemetry-instrumentation-rack"
gem "opentelemetry-instrumentation-sinatra"       # if using Sinatra

# HTTP clients
gem "opentelemetry-instrumentation-faraday"
gem "opentelemetry-instrumentation-net_http"
gem "opentelemetry-instrumentation-ethon"          # if using Typhoeus
gem "opentelemetry-instrumentation-excon"
gem "opentelemetry-instrumentation-http_client"
gem "opentelemetry-instrumentation-httpx"

# Database
gem "opentelemetry-instrumentation-pg"
gem "opentelemetry-instrumentation-mysql2"
gem "opentelemetry-instrumentation-trilogy"
gem "opentelemetry-instrumentation-active_record"

# Rails sub-components (included by rails instrumentation)
gem "opentelemetry-instrumentation-action_pack"
gem "opentelemetry-instrumentation-action_view"
gem "opentelemetry-instrumentation-action_mailer"
gem "opentelemetry-instrumentation-active_job"
gem "opentelemetry-instrumentation-active_storage"
gem "opentelemetry-instrumentation-active_support"

# Background jobs
gem "opentelemetry-instrumentation-sidekiq"
gem "opentelemetry-instrumentation-resque"
gem "opentelemetry-instrumentation-delayed_job"

# Caching & messaging
gem "opentelemetry-instrumentation-redis"
gem "opentelemetry-instrumentation-aws_sdk"
gem "opentelemetry-instrumentation-bunny"          # RabbitMQ
gem "opentelemetry-instrumentation-rdkafka"        # Kafka
gem "opentelemetry-instrumentation-racecar"        # Kafka consumer

# Other
gem "opentelemetry-instrumentation-concurrent_ruby"
gem "opentelemetry-instrumentation-graphql"
gem "opentelemetry-instrumentation-grape"
```

### Logs (Experimental)

```ruby
gem "opentelemetry-logs-sdk"
gem "opentelemetry-exporter-otlp-logs"
```

---

## SDK Configuration

### Rails Initializer

Create `config/initializers/opentelemetry.rb`:

```ruby
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"  # or require individual gems

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "my-service")

  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    "deployment.environment" => ENV.fetch("RAILS_ENV", "development"),
    "service.version" => ENV.fetch("APP_VERSION", "0.0.0")
  )

  c.use_all  # Enable all installed instrumentation gems
end
```

### Selective Instrumentation

Instead of `c.use_all`, enable only specific instrumentations with configuration options:

```ruby
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "my-service")

  c.use "OpenTelemetry::Instrumentation::Rails"
  c.use "OpenTelemetry::Instrumentation::Rack"
  c.use "OpenTelemetry::Instrumentation::Faraday"
  c.use "OpenTelemetry::Instrumentation::PG", {
    db_statement: :obfuscate  # :include, :obfuscate, or :omit
  }
  c.use "OpenTelemetry::Instrumentation::ActiveRecord"
  c.use "OpenTelemetry::Instrumentation::ActiveJob"
  c.use "OpenTelemetry::Instrumentation::Net::HTTP"
  c.use "OpenTelemetry::Instrumentation::Redis", {
    db_statement: :obfuscate
  }
end
```

### API-Only Rails Applications

For API-only apps (e.g., `config.api_only = true`), the same initializer works. The `rails` instrumentation adapts automatically. You may skip `action_view` if there are no templates:

```ruby
OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "my-api")

  c.use "OpenTelemetry::Instrumentation::Rails"
  c.use "OpenTelemetry::Instrumentation::Rack"
  c.use "OpenTelemetry::Instrumentation::ActionPack"
  c.use "OpenTelemetry::Instrumentation::ActiveRecord"
  c.use "OpenTelemetry::Instrumentation::PG"
  c.use "OpenTelemetry::Instrumentation::Faraday"
end
```

---

## Environment Variables

OpenTelemetry Ruby SDK respects standard `OTEL_*` environment variables. Prefer environment variables over hardcoding values.

### Essential Variables

```bash
# Service identity
OTEL_SERVICE_NAME=my-service

# Exporter endpoint (OTLP HTTP default)
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

# Protocol: http/protobuf (default) or grpc
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# Resource attributes (comma-separated key=value pairs)
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.version=1.2.0
```

### Exporter & Processor Variables

```bash
# Auth headers (for SaaS backends)
OTEL_EXPORTER_OTLP_HEADERS=api-key=your-key-here

# Compression
OTEL_EXPORTER_OTLP_COMPRESSION=gzip

# Signal-specific endpoints (override the base endpoint)
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4318/v1/traces
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://localhost:4318/v1/metrics
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://localhost:4318/v1/logs

# Span processor tuning
OTEL_BSP_MAX_QUEUE_SIZE=2048
OTEL_BSP_SCHEDULE_DELAY=5000
OTEL_BSP_MAX_EXPORT_BATCH_SIZE=512
OTEL_BSP_EXPORT_TIMEOUT=30000

# Sampling (1.0 = always, 0.0 = never)
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1

# Propagators (default: tracecontext,baggage)
OTEL_PROPAGATORS=tracecontext,baggage

# Disable SDK (useful for test environments)
OTEL_SDK_DISABLED=true

# Log level for OTel internal diagnostics
OTEL_LOG_LEVEL=info
```

### Docker Compose Example

```yaml
services:
  my-service:
    environment:
      OTEL_SERVICE_NAME: my-service
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4318
      OTEL_RESOURCE_ATTRIBUTES: "deployment.environment=production,service.namespace=my-app"
```

---

## Manual Instrumentation

### Acquiring a Tracer

```ruby
# Define a tracer — typically once per class or module
module MyApp
  TRACER = OpenTelemetry.tracer_provider.tracer("my-app", "1.0.0")
end
```

### Creating Custom Spans

```ruby
MyApp::TRACER.in_span("process-order", attributes: { "order.id" => order.id }) do |span|
  # Business logic here
  span.set_attribute("order.total", order.total.to_f)
  span.set_attribute("order.item_count", order.items.count)

  result = process(order)
  span.set_attribute("order.status", result.status)
end
```

### Span Kinds

```ruby
# :internal (default), :server, :client, :producer, :consumer
MyApp::TRACER.in_span("http-request", kind: :client) do |span|
  # outbound HTTP call
end

MyApp::TRACER.in_span("process-message", kind: :consumer) do |span|
  # processing a message from a queue
end
```

### Adding Events

```ruby
MyApp::TRACER.in_span("checkout") do |span|
  span.add_event("payment.initiated", attributes: {
    "payment.method" => "credit_card",
    "payment.amount" => 99.50
  })

  charge_payment!

  span.add_event("payment.completed", attributes: {
    "payment.transaction_id" => txn.id
  })
end
```

### Exception Handling

The `in_span` helper automatically calls `record_exception` and sets `status = error` when the block raises — no manual rescue needed:

```ruby
# Preferred — in_span handles exception recording and status automatically
MyApp::TRACER.in_span("risky-operation") do |span|
  span.set_attribute("order.id", order.id)
  perform_risky_work
end
```

Only use manual `record_exception` when you need to record an error but **not** re-raise:

```ruby
MyApp::TRACER.in_span("best-effort-operation") do |span|
  perform_work
rescue SomeNonFatalError => e
  span.record_exception(e)
  span.status = OpenTelemetry::Trace::Status.error(e.message)
  # intentionally swallowed — operation is best-effort
end
```

### Setting Span Status

```ruby
# Mark a span as OK explicitly
span.status = OpenTelemetry::Trace::Status.ok

# Mark a span as error with a description
span.status = OpenTelemetry::Trace::Status.error("Payment gateway timeout")
```

### Nested Spans

```ruby
MyApp::TRACER.in_span("parent-operation") do |parent_span|
  # Automatically becomes a child span
  MyApp::TRACER.in_span("child-operation") do |child_span|
    child_span.set_attribute("step", "validation")
  end
end
```

---

## Context Propagation

### How It Works

OpenTelemetry uses W3C TraceContext headers (`traceparent`, `tracestate`) and Baggage headers by default. When you instrument both HTTP clients and servers, context propagation happens automatically.

**Automatic flow:**
1. Service A creates a span for an outgoing HTTP request
2. The Faraday/Net::HTTP instrumentation injects `traceparent` header
3. Service B receives the request
4. The Rack instrumentation extracts `traceparent` and creates a child span
5. The trace is now connected across both services

### Verify Propagation Is Working

Traces across services share the same `trace_id`. If you see disconnected traces, check:
- Both services have `opentelemetry-instrumentation-rack` (server side)
- The calling service has `opentelemetry-instrumentation-faraday` or `opentelemetry-instrumentation-net_http` (client side)
- No middleware is stripping `traceparent` headers

### Manual Propagation (Advanced)

For custom transports where auto-instrumentation doesn't apply:

```ruby
# Inject context into a carrier (e.g., HTTP headers hash)
headers = {}
OpenTelemetry.propagation.inject(headers)
# headers now contains { "traceparent" => "00-...", "tracestate" => "..." }
# Send headers with your custom transport

# Extract context from incoming carrier
context = OpenTelemetry.propagation.extract(incoming_headers)
OpenTelemetry::Context.with_current(context) do
  MyApp::TRACER.in_span("process-message", kind: :consumer) do |span|
    # This span is now a child of the extracted trace context
  end
end
```

### Propagation with Background Jobs

For ActiveJob / Sidekiq / Resque, the auto-instrumentation gems handle propagation automatically. For custom job systems:

```ruby
# Enqueuing — inject context into job payload
class MyJob
  def self.enqueue(payload)
    metadata = {}
    OpenTelemetry.propagation.inject(metadata)
    queue.push(payload.merge(otel_context: metadata))
  end
end

# Processing — extract context from job payload
class MyWorker
  def perform(job_data)
    context = OpenTelemetry.propagation.extract(job_data[:otel_context] || {})
    OpenTelemetry::Context.with_current(context) do
      MyApp::TRACER.in_span("process-job", kind: :consumer) do |span|
        # Process the job
      end
    end
  end
end
```

---

## Instrumenting Faraday HTTP Clients

The `opentelemetry-instrumentation-faraday` gem automatically instruments all Faraday connections when enabled via `c.use_all` or `c.use "OpenTelemetry::Instrumentation::Faraday"`.

### What It Does Automatically

- Creates client spans for each HTTP request
- Sets span attributes: `http.method`, `http.url`, `http.status_code`, `net.peer.name`
- Injects W3C `traceparent` and `tracestate` headers for cross-service propagation
- Records errors when the request fails

### Adding Custom Attributes

```ruby
class ShippingClient
  TRACER = OpenTelemetry.tracer_provider.tracer("shipping-client")

  def calculate_rates(origin:, destination:, package:)
    TRACER.in_span("shipping.calculate_rates", kind: :client) do |span|
      span.set_attribute("shipping.origin", origin[:zip])
      span.set_attribute("shipping.destination", destination[:zip])
      span.set_attribute("shipping.weight", package[:weight])

      response = @connection.post("/api/v1/rates") do |req|
        req.body = { origin:, destination:, package: }
      end

      span.set_attribute("shipping.rates_count", response.body["rates"]&.size || 0)
      response.body
    end
  end
end
```

---

## Instrumenting Rails Controllers

Auto-instrumentation creates spans for controller actions automatically. Add business context with custom attributes:

```ruby
class OrdersController < ApplicationController
  def create
    current_span = OpenTelemetry::Trace.current_span
    current_span.set_attribute("user.id", current_user.id)
    current_span.set_attribute("order.item_count", order_params[:items].size)

    @order = OrderService.new.create(order_params)

    current_span.set_attribute("order.id", @order.id)
    current_span.set_attribute("order.total", @order.total.to_f)
  end
end
```

---

## Instrumenting Event Subscribers and Callbacks

For Rails event subscribers or pub/sub patterns, wrap handlers in spans:

```ruby
class OrderNotificationSubscriber
  TRACER = OpenTelemetry.tracer_provider.tracer("order-notifications")

  def order_finalized(event)
    order = event.payload[:order]
    return unless order

    TRACER.in_span("notification.order_finalized",
      attributes: {
        "order.id" => order.id,
        "order.number" => order.number
      }
    ) do |span|
      NotificationClient.new.order_placed(order)
    rescue NotificationClient::NotificationError => e
      # Best-effort — log and swallow so the order flow isn't interrupted
      span.record_exception(e)
      span.status = OpenTelemetry::Trace::Status.error(e.message)
      Rails.logger.warn("[OrderNotificationSubscriber] #{e.message}")
    end
  end
end
```

---

## Instrumenting Service Objects

```ruby
class ProcessPaymentService
  TRACER = OpenTelemetry.tracer_provider.tracer("payment-service")

  def call(order:, payment_method:)
    TRACER.in_span("payment.process",
      attributes: {
        "order.id" => order.id,
        "payment.method" => payment_method.type
      }
    ) do |span|
      result = gateway.charge(order.total, payment_method)

      span.set_attribute("payment.transaction_id", result.transaction_id)
      span.set_attribute("payment.status", result.status)

      if result.success?
        span.status = OpenTelemetry::Trace::Status.ok
      else
        span.status = OpenTelemetry::Trace::Status.error(result.error_message)
      end

      result
    end
  end
end
```

---

## Semantic Conventions

Use standard OpenTelemetry semantic conventions for attribute names to ensure compatibility with observability backends.

### HTTP

| Attribute | Description | Example |
|-----------|-------------|---------|
| `http.request.method` | HTTP method | `GET`, `POST` |
| `http.response.status_code` | HTTP status code | `200`, `404` |
| `url.full` | Full URL | `https://api.example.com/v1/users` |
| `url.path` | URL path | `/v1/users` |
| `server.address` | Server hostname | `api.example.com` |
| `server.port` | Server port | `443` |

### Database

| Attribute | Description | Example |
|-----------|-------------|---------|
| `db.system` | Database type | `postgresql`, `mysql`, `redis` |
| `db.namespace` | Database name | `my_app_production` |
| `db.operation.name` | Operation | `SELECT`, `INSERT` |
| `db.query.text` | Query (obfuscated) | `SELECT * FROM users WHERE id = ?` |

### Messaging

| Attribute | Description | Example |
|-----------|-------------|---------|
| `messaging.system` | Messaging system | `kafka`, `rabbitmq`, `sidekiq` |
| `messaging.operation.type` | Operation | `publish`, `receive`, `process` |
| `messaging.destination.name` | Queue/topic name | `order-events` |

### Custom Business Attributes

Prefix custom attributes with your domain to avoid collisions:

```ruby
span.set_attribute("app.user.id", user.id)
span.set_attribute("app.order.total", order.total.to_f)
span.set_attribute("app.feature_flag.variant", variant_name)
```

---

## Exporters

### OTLP HTTP (Default & Recommended)

```ruby
# Gemfile
gem "opentelemetry-exporter-otlp", "~> 0.31"
```

Configured automatically via environment variables:
```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

### Console Exporter (Development / Debugging)

Prints spans to STDOUT — useful for local development:

```ruby
# config/initializers/opentelemetry.rb
require "opentelemetry/sdk"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "my-service"
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  )
  c.use_all
end
```

### Multiple Exporters

Send traces to both a collector and the console:

```ruby
OpenTelemetry::SDK.configure do |c|
  c.service_name = "my-service"

  # OTLP to collector
  otlp_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otlp_exporter)
  )

  # Console for debugging
  if Rails.env.development?
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      )
    )
  end

  c.use_all
end
```

---

## Sampling

### Head-Based Sampling

Configure via environment variables:

```bash
# Always sample (development)
OTEL_TRACES_SAMPLER=always_on

# Never sample (disable tracing)
OTEL_TRACES_SAMPLER=always_off

# Sample 10% of new traces, honor parent decisions
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

### Programmatic Sampling

```ruby
OpenTelemetry::SDK.configure do |c|
  c.service_name = "my-service"

  # Custom sampler: sample 10% of traces, always honor parent
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new
    )
  )

  c.use_all
end
```

---

## Logs Integration

### Trace-Correlated Logging

Add trace context to Rails logs so log lines can be correlated with traces in your observability backend:

```ruby
# config/initializers/opentelemetry.rb (add after SDK configuration)

# Extend the Rails logger formatter to include trace context
module OtelLogFormatter
  def call(severity, timestamp, progname, msg)
    span_context = OpenTelemetry::Trace.current_span.context
    if span_context.valid?
      trace_id = span_context.hex_trace_id
      span_id = span_context.hex_span_id
      "[#{severity}] [trace_id=#{trace_id} span_id=#{span_id}] #{msg}\n"
    else
      "[#{severity}] #{msg}\n"
    end
  end
end

Rails.logger.formatter.extend(OtelLogFormatter) if Rails.logger.formatter
```

### Structured Logging with Lograge

```ruby
# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    span_context = OpenTelemetry::Trace.current_span.context
    {
      trace_id: span_context.valid? ? span_context.hex_trace_id : nil,
      span_id: span_context.valid? ? span_context.hex_span_id : nil
    }
  end
end
```

### OpenTelemetry Logs SDK (Experimental)

```ruby
require "opentelemetry-logs-sdk"
require "opentelemetry/exporter/otlp_logs"

log_exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(
  endpoint: ENV.fetch("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "http://localhost:4318/v1/logs")
)
processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(log_exporter)
OpenTelemetry.logger_provider.add_log_record_processor(processor)
```

---

## Testing

### Disabling OTel in Tests

```bash
# test environment
OTEL_SDK_DISABLED=true
```

Or in the test helper:

```ruby
# test/test_helper.rb or spec/spec_helper.rb
ENV["OTEL_SDK_DISABLED"] = "true"
```

### Testing Spans

Use the SDK's in-memory exporter to verify instrumentation:

```ruby
require "opentelemetry/sdk"

RSpec.describe ProcessPaymentService do
  let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }

  before do
    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
      )
    end
  end

  after { exporter.reset }

  it "creates a payment span" do
    described_class.new.call(order: order, payment_method: method)

    spans = exporter.finished_spans
    payment_span = spans.find { |s| s.name == "payment.process" }

    expect(payment_span).not_to be_nil
    expect(payment_span.attributes["order.id"]).to eq(order.id)
    expect(payment_span.attributes["payment.method"]).to eq("credit_card")
    expect(payment_span.status.code).to eq(OpenTelemetry::Trace::Status::OK)
  end
end
```

### Minitest Example

```ruby
require "opentelemetry/sdk"

class ProcessPaymentServiceTest < ActiveSupport::TestCase
  setup do
    @exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@exporter)
      )
    end
  end

  teardown { @exporter.reset }

  test "creates a payment span with correct attributes" do
    ProcessPaymentService.new.call(order: order, payment_method: method)

    spans = @exporter.finished_spans
    payment_span = spans.find { |s| s.name == "payment.process" }

    assert_not_nil payment_span
    assert_equal order.id, payment_span.attributes["order.id"]
  end
end
```

---

## Quick Start Checklist

1. **Add gems** to `Gemfile` (`opentelemetry-sdk`, `opentelemetry-exporter-otlp`, instrumentation gems)
2. **Run** `bundle install`
3. **Create initializer** at `config/initializers/opentelemetry.rb`
4. **Set environment variables** (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`)
5. **Add OTel Collector** to `docker-compose.yml`
6. **Add a trace backend** (Jaeger, Tempo, or SaaS)
7. **Start services** and verify traces appear in the backend
8. **Add custom spans** to business-critical code paths
9. **Add trace context** to logs for correlation
10. **Configure sampling** for production traffic volume

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No traces appearing | Exporter endpoint wrong or collector down | Check `OTEL_EXPORTER_OTLP_ENDPOINT` and collector logs |
| Traces not connected across services | Missing client or server instrumentation | Ensure both Faraday/Net::HTTP (client) and Rack (server) instrumentations are enabled |
| `traceparent` header not injected | HTTP client instrumentation not loaded | Verify the Faraday or Net::HTTP instrumentation gem is installed and enabled |
| Duplicate spans | Multiple instrumentations overlapping | Don't use both `pg` and `active_record` instrumentations unless needed |
| Slow startup | Loading all instrumentations | Switch from `use_all` to selective `use` calls |
| Spans missing attributes | Attributes set after span ends | Set attributes inside the `in_span` block before it closes |
| Console exporter shows nothing | Using `BatchSpanProcessor` with short-lived process | Use `SimpleSpanProcessor` for scripts and console exporter |

---

## References

- [OpenTelemetry Ruby Official Docs](https://opentelemetry.io/docs/languages/ruby/)
- [OpenTelemetry Ruby SDK GitHub](https://github.com/open-telemetry/opentelemetry-ruby)
- [OpenTelemetry Ruby Contrib (Instrumentations)](https://github.com/open-telemetry/opentelemetry-ruby-contrib)
- [Instrumentation Registry & API Docs](https://open-telemetry.github.io/opentelemetry-ruby/)
- [Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [W3C TraceContext Specification](https://www.w3.org/TR/trace-context/)

## Related

- **Skill: `otel-collector`** — Collector setup, configuration, Docker Compose, and backend integration
- **Instructions: `opentelemetry-ruby`** — Coding conventions and best practices for OTel in Ruby
