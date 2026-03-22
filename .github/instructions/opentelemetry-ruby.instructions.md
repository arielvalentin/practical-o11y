---
description: 'OpenTelemetry instrumentation conventions and best practices for Ruby applications'
applyTo: '**/*.rb'
---

# OpenTelemetry Ruby Best Practices

## Span Naming

- Use **lowercase dot-delimited** names: `order.create`, `payment.process`, `notification.send`
- For HTTP server spans, let the framework auto-generate names like `GET /api/v1/orders`
- For HTTP client spans, let the instrumentation generate names like `HTTP GET`
- Keep names low-cardinality — never include IDs or variable data in span names

## Attributes

- Use semantic convention attribute names when they exist
- Prefix custom attributes with a namespace: `app.`, `biz.`, or your domain
- Keep attribute values low-cardinality when possible
- Never put sensitive data (passwords, tokens, PII) in attributes
- Attribute values must be strings, integers, floats, booleans, or arrays thereof

## Error Handling

- Always `record_exception` and set `status = error` when catching exceptions in spans
- Re-raise exceptions after recording them — don't swallow errors
- Set `status = ok` only when you want to explicitly mark success (unset is also valid)

```ruby
begin
  perform_work
rescue StandardError => e
  span.record_exception(e)
  span.status = OpenTelemetry::Trace::Status.error(e.message)
  raise
end
```

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
- Add health checks to the collector and backends
- Use `depends_on` with `condition: service_healthy` for startup ordering
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
