---
description: 'OpenTelemetry instrumentation conventions and best practices for Ruby applications'
applyTo: '**/*.rb'
---

# OpenTelemetry Ruby Best Practices

## Library Instrumentation First

- Always prefer library instrumentation (auto-instrumentation gems) over manual instrumentation
- Only add manual spans when library instrumentation does not cover a code path (e.g., custom business logic, event subscribers, domain-specific operations)
- Do not re-implement what library instrumentation already provides — enrich existing spans with custom attributes instead

## Span Naming

- Use **lowercase dot-delimited** names: `order.create`, `payment.process`, `notification.send`
- For HTTP server spans, let the framework auto-generate names like `GET /api/v1/orders`
- For HTTP client spans, let the instrumentation generate names like `HTTP GET`
- Keep names low-cardinality — never include IDs or variable data in span names

## Attributes

- Use `add_attributes` (hash) instead of multiple `set_attribute` calls — it is more efficient and readable
- Only use `set_attribute` when setting a single attribute in isolation (e.g., after a conditional branch)
- Pass known attributes directly to `in_span` via the `attributes:` keyword when possible
- Use semantic convention attribute names when they exist
- Prefix custom attributes with a namespace: `app.`, `biz.`, or your domain
- Keep attribute values low-cardinality when possible
- Never put sensitive data (passwords, tokens, PII) in attributes
- Attribute values must be strings, integers, floats, booleans, or arrays thereof

## Error Handling

- Let `Tracer#in_span` handle exception recording automatically — it calls `record_exception` and sets `status = error` when the block raises
- Do not manually rescue, `record_exception`, and re-raise inside an `in_span` block — that duplicates what the helper already does
- Set `status = ok` only when you want to explicitly mark success (unset is also valid)

```ruby
# Preferred — in_span records the exception and sets error status automatically
tracer.in_span("process-order", attributes: { "app.order.id" => order.id }) do |span|
  perform_work
end
```

## Spans

- Prefer enriching the current span (`OpenTelemetry::Trace.current_span`) over creating child spans
- Only create child spans for distinct units of work (loop iterations, parallel tasks, clearly separate operations)
- When library instrumentation already creates a span (e.g., Faraday HTTP client span), enrich it with `add_attributes` instead of wrapping it in another `in_span`

## Performance

- Use `BatchSpanProcessor` in production (not `SimpleSpanProcessor`)
- Check `span.recording?` before doing expensive attribute computation
- Don't create spans for trivially fast operations (< 1ms) unless they cross service boundaries
- Use sampling to control volume in high-throughput services

## Instrumentation Scope

- Define tracers at the module or class level, not per-request
- Use a descriptive tracer name matching the component: `"shipping-client"`, `"payment-service"`
- Include a version string in the tracer for change tracking

```ruby
module MyService
  TRACER = OpenTelemetry.tracer_provider.tracer("my-service", "1.0.0")
end
```

## SDK Configuration

- Prefer environment variables (`OTEL_*`) over hardcoded configuration values
- Use selective `c.use` calls in production instead of `c.use_all` to control startup time and reduce noise
- Obfuscate database statements in production: `db_statement: :obfuscate`
- Set `OTEL_SDK_DISABLED=true` in test environments

## Multi-Service Architecture

- Always use the OTel Collector as an intermediary — don't export directly to backends from services
- Ensure every service sets `OTEL_SERVICE_NAME` to a unique, descriptive name
- Use `service.namespace` resource attribute to group related services
- Test trace propagation across service boundaries early in development

## Docker Compose

- Configure `OTEL_EXPORTER_OTLP_ENDPOINT` to point to the collector's Docker service name (e.g., `http://otel-collector:4318`)
- Set `OTEL_SDK_DISABLED=true` in test/CI containers

## Testing Instrumentation

- Use `OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter` to assert on spans in tests
- Use `SimpleSpanProcessor` (not `BatchSpanProcessor`) in test setup for synchronous span export
- Reset the exporter between tests to avoid cross-test contamination
- Assert on span names, attributes, status, and parent-child relationships

## Logging

- Correlate logs with traces by including `trace_id` and `span_id` in log output
- Use structured logging (JSON) with Lograge or similar for machine-parseable log lines
- Never log full span or trace objects — log only the hex IDs
- Do not use `Rails.logger` with string interpolation — use structured logging or span events instead
