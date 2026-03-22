# Practical Observability — Ruby on Rails + OpenTelemetry

A hands-on demo showing how to instrument Ruby on Rails applications with [OpenTelemetry](https://opentelemetry.io/). Walk through a real multi-service ecommerce platform — from zero instrumentation to full distributed tracing.

## What's Inside

| Directory | Description |
|-----------|-------------|
| `ruby/` | **Baseline** — uninstrumented Rails services |
| `ruby-o11y/` | **Instrumented** — same services with OpenTelemetry tracing ([branch](https://github.com/arielvalentin/practical-o11y/tree/opentelemetry-ruby-instrumentation)) |

## Architecture

Four Rails services communicate over HTTP, demonstrating different OpenTelemetry trace scenarios:

```
┌──────────────┐    HTTP     ┌──────────────────────┐
│              │────────────▶│  Shipping Service    │
│              │             │  :3001               │
│              │             └──────────────────────┘
│              │
│    Spree     │    HTTP     ┌──────────────────────┐
│    Store     │────────────▶│  Recommendation Svc  │
│    :3000     │             │  :3002               │
│              │             └──────────────────────┘
│              │
│              │    HTTP     ┌──────────────────────┐
│              │────────────▶│  Notification Svc    │
│              │             │  :3003               │
└──────┬───────┘             └──────────┬───────────┘
       │                                │
       │         ┌──────────┐           │
       └────────▶│PostgreSQL│◀──────────┘
                 │  :5432   │
                 └──────────┘
```

### Services

| Service | Port | Stack | Description |
|---------|------|-------|-------------|
| **Store** | 3000 | Spree Commerce (full-stack Rails) | Storefront, admin, API |
| **Shipping** | 3001 | Rails API | Mock shipping rate calculator |
| **Recommendations** | 3002 | Rails API | Mock product recommendation engine |
| **Notifications** | 3003 | Rails API | Email/notification dispatcher with DB persistence |

### Trace Scenarios

- **Store → Shipping** — Synchronous HTTP during checkout (client/server spans)
- **Store → Recommendations** — Synchronous HTTP on product pages (cross-service traces)
- **Store → Notifications** — Event-driven via Spree subscribers (async tracing)

## What You'll Learn

1. **Auto-instrumentation** — How `opentelemetry-instrumentation-all` automatically traces Rails, Rack, ActiveRecord, Faraday, and PG
2. **Custom spans** — Wrapping business logic with meaningful spans and domain-specific attributes
3. **Context propagation** — W3C `traceparent` headers flowing across HTTP boundaries via Faraday
4. **Error recording** — Using `span.record_exception` and `span.status` for proper error visibility
5. **OTel Collector** — Receiving, batching, and exporting traces to Jaeger
6. **Span naming** — Low-cardinality `{verb} {object}` naming conventions
7. **Attribute conventions** — Following OTel semantic conventions + domain-specific attributes

## Quick Start

### Baseline (no instrumentation)

```bash
cd ruby
docker compose up --build
```

### Instrumented (with OpenTelemetry)

```bash
git checkout opentelemetry-ruby-instrumentation
cd ruby-o11y
docker compose up --build
```

Then open:
- **Storefront** — http://localhost:3000
- **Jaeger UI** — http://localhost:16686 (trace visualization)

### Database Setup

```bash
docker compose exec store bin/rails db:create db:migrate
docker compose exec store bin/rails db:seed AUTO_ACCEPT=1
docker compose exec store bin/rails spree_sample:load
docker compose exec notifications bin/rails db:create db:migrate
```

## Load Testing

Install [k6](https://k6.io/) (`brew install k6`), then:

```bash
K6_WEB_DASHBOARD=true k6 run ruby/k6/load-test.js
```

Generates traffic across all services to produce rich distributed traces.

## Tech Stack

- **Ruby** 4.0+ / **Rails** 8.1
- **Spree Commerce** 5.3
- **OpenTelemetry Ruby SDK** + auto-instrumentation
- **OTel Collector** (contrib distribution)
- **Jaeger** (trace visualization)
- **PostgreSQL** 17
- **Docker Compose**

## Copilot Integration

This repo includes Copilot instructions and skills for OpenTelemetry instrumentation:

- `.github/instructions/opentelemetry-ruby.instructions.md` — Auto-applies OTel conventions when editing Ruby files
- `.agents/skills/opentelemetry-ruby/` — Reusable Copilot skill for OTel instrumentation tasks

## License

This project is licensed under the [MIT License](LICENSE).
