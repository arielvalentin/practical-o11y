# Practical Observability — Ruby on Rails + OpenTelemetry Demo

A multi-service ecommerce platform built with Ruby on Rails, instrumented with OpenTelemetry for distributed tracing.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Docker Compose                                │
│                                                                         │
│  ┌──────────────┐    HTTP     ┌──────────────────────┐                 │
│  │              │────────────▶│  Shipping Service    │                 │
│  │              │             │  :3001               │                 │
│  │              │             │  POST /api/v1/rates   │                 │
│  │              │             └──────────┬───────────┘                 │
│  │              │                        │                              │
│  │    Spree     │    HTTP     ┌──────────────────────┐                 │
│  │    Store     │────────────▶│  Recommendation Svc  │                 │
│  │    :3000     │             │  :3002               │                 │
│  │              │             │  GET /api/v1/recs     │                 │
│  │              │             └──────────┬───────────┘                 │
│  │              │                        │                              │
│  │              │    HTTP     ┌──────────────────────┐                 │
│  │              │────────────▶│  Notification Svc    │                 │
│  │              │             │  :3003               │                 │
│  │              │             │  POST /api/v1/notifs  │                 │
│  └──────┬───────┘             └──────────┬───────────┘                 │
│         │                                │                              │
│     OTLP│    ┌──────────┐           OTLP│                              │
│         │    │PostgreSQL│                │                              │
│         │    │  :5432   │                │                              │
│         │    └──────────┘                │                              │
│         ▼                                ▼                              │
│  ┌─────────────────────────────────────────┐                           │
│  │          OTel Collector :4318           │                           │
│  │          (OTLP HTTP receiver)           │                           │
│  └──────────────────┬──────────────────────┘                           │
│                     │ OTLP gRPC                                         │
│                     ▼                                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐                         │
│  │  Tempo   │  │Prometheus│  │   Grafana    │                         │
│  │  :3200   │  │  :9090   │  │   :3100      │                         │
│  └──────────┘  └──────────┘  └──────────────┘                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| **Store** | 3000 | Main Spree Commerce app — storefront, admin, API |
| **Shipping** | 3001 | Mock shipping rate calculator (ground, express, overnight) |
| **Recommendations** | 3002 | Mock product recommendation engine |
| **Notifications** | 3003 | Email/notification dispatcher with DB persistence |
| **PostgreSQL** | 5432 | Shared database (separate DB per service) |
| **OTel Collector** | 4318 | Receives OTLP telemetry from all services |
| **Tempo** | 3200 | Distributed trace storage backend |
| **Prometheus** | 9090 | Metrics (collector self-monitoring) |
| **Grafana** | 3100 | Observability UI — traces, metrics |

## Communication Patterns

These patterns are designed to showcase different OpenTelemetry trace scenarios:

- **Store → Shipping**: Synchronous HTTP during checkout (demonstrates HTTP client/server spans)
- **Store → Recommendations**: Synchronous HTTP on product pages (demonstrates cross-service traces)
- **Store → Notifications**: Event-driven via Spree subscribers (demonstrates async/background job tracing)

## Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- Ruby 4.0+ (for local development without Docker)

### Start Everything

```bash
cd ruby-o11y
docker compose up --build
```

### Setup Databases

In a separate terminal:

```bash
# Run migrations for each service
docker compose exec store bin/rails db:create db:migrate
docker compose exec store bin/rails db:seed AUTO_ACCEPT=1
docker compose exec store bin/rails spree_sample:load
docker compose exec notifications bin/rails db:create db:migrate
```

The shipping and recommendation services are stateless (no migrations needed).

### Access

| URL | Description |
|-----|-------------|
| http://localhost:3000 | Storefront |
| http://localhost:3000/admin | Admin Panel (spree@example.com / spree123) |
| http://localhost:3001/api/v1/health | Shipping service health |
| http://localhost:3002/api/v1/health | Recommendation service health |
| http://localhost:3003/api/v1/health | Notification service health |
| http://localhost:3100 | Grafana UI (admin / admin) |
| http://localhost:3200 | Tempo HTTP API |
| http://localhost:9090 | Prometheus UI |
| http://localhost:13133 | OTel Collector health check |

## API Examples

### Shipping Rates

```bash
curl -X POST http://localhost:3001/api/v1/rates \
  -H "Content-Type: application/json" \
  -d '{
    "origin": {"zip": "10001", "city": "New York", "state": "NY", "country": "US"},
    "destination": {"zip": "90210", "city": "Beverly Hills", "state": "CA", "country": "US"},
    "package": {"weight": 2.5, "length": 10, "width": 8, "height": 4}
  }'
```

### Product Recommendations

```bash
curl "http://localhost:3002/api/v1/recommendations?product_id=prod_001&limit=3"
```

### Send Notification

```bash
curl -X POST http://localhost:3003/api/v1/notifications \
  -H "Content-Type: application/json" \
  -d '{
    "notification": {
      "type": "order_placed",
      "recipient": "customer@example.com",
      "payload": {"order_number": "R123456789"}
    }
  }'
```

### List Notifications

```bash
curl "http://localhost:3003/api/v1/notifications?limit=10"
```

## Load Testing

Install [k6](https://k6.io/) (`brew install k6`), then:

```bash
# Run with live dashboard (http://localhost:5665)
K6_WEB_DASHBOARD=true k6 run ruby-o11y/k6/load-test.js

# Export a standalone HTML report you can open anytime
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=k6-report.html k6 run ruby-o11y/k6/load-test.js

# Keep the live dashboard open after the test finishes (Ctrl+C to stop)
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_OPEN=true k6 run --pause-after ruby-o11y/k6/load-test.js
```

The test runs four scenarios in parallel for 2 minutes:

| Scenario | Type | Description |
|---|---|---|
| `browse` | HTTP | Simulates users browsing the storefront (1→10 VUs) |
| `api_calls` | HTTP | Hits microservice APIs directly at 10 req/s |
| `store_api_calls` | HTTP | Hits microservices via store proxy at 5 req/s |
| `browser_users` | Chromium | Real browser user journeys (1→3 VUs) |

## Project Structure

```
ruby-o11y/
├── docker-compose.yml           # Orchestrates all services + observability stack
├── otel-collector-config.yaml   # OTel Collector pipeline configuration
├── tempo-config.yaml            # Grafana Tempo trace storage config
├── grafana-datasources.yaml     # Grafana auto-provisioned datasources
├── prometheus.yaml              # Prometheus scrape config
├── init-databases.sql           # Creates databases on first run
├── store/                       # Spree Commerce (Rails full-stack)
│   ├── app/clients/             # HTTP clients for microservices
│   ├── app/subscribers/         # Spree event subscribers
│   ├── config/initializers/opentelemetry.rb  # OTel SDK setup
│   └── ...
├── shipping-service/            # Rails API
│   ├── app/services/            # ShippingRateCalculator
│   ├── config/initializers/opentelemetry.rb  # OTel SDK setup
│   └── ...
├── recommendation-service/      # Rails API
│   ├── app/services/            # RecommendationEngine
│   ├── config/initializers/opentelemetry.rb  # OTel SDK setup
│   └── ...
└── notification-service/        # Rails API
    ├── app/services/            # NotificationDispatcher
    ├── app/models/              # Notification (persisted)
    ├── config/initializers/opentelemetry.rb  # OTel SDK setup
    └── ...
```

## OpenTelemetry Instrumentation

### What's Instrumented

All services use auto-instrumentation with selective `c.use` calls:

| Instrumentation | Store | Shipping | Recommendations | Notifications |
|-----------------|-------|----------|-----------------|---------------|
| Rails | ✅ | ✅ | ✅ | ✅ |
| Rack | ✅ | ✅ | ✅ | ✅ |
| PG | ✅ | ✅ | ✅ | ✅ |
| ActiveRecord | ✅ | ✅ | ✅ | ✅ |
| Faraday | ✅ | — | — | — |
| Net::HTTP | ✅ | — | — | — |
| ActiveJob | ✅ | — | — | — |
| ActiveSupport | ✅ | — | — | — |

### Context Propagation

Distributed tracing works automatically:

1. **Store** makes an HTTP request via Faraday to a downstream service
2. Faraday instrumentation **injects** `traceparent` header into the request
3. Downstream service's Rack instrumentation **extracts** `traceparent` and creates a child span
4. The trace is connected across both services with the same `trace_id`

### Viewing Traces

1. Start all services: `docker compose up --build`
2. Generate traffic (browse the store, run k6 load tests, or call APIs directly)
3. Open **Grafana** at [http://localhost:3100](http://localhost:3100)
4. Navigate to **Explore** → select **Tempo** datasource
5. Search for traces by service name, duration, or status

### Environment Variables

Each service is configured with these OTel environment variables in `docker-compose.yml`:

| Variable | Description | Example |
|----------|-------------|---------|
| `OTEL_SERVICE_NAME` | Unique service identifier | `store`, `shipping-service` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Collector endpoint | `http://otel-collector:4318` |
| `OTEL_RESOURCE_ATTRIBUTES` | Resource metadata | `deployment.environment=production` |

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| No traces in Grafana | Check collector logs: `docker compose logs otel-collector` |
| Traces not connected across services | Verify Faraday instrumentation is enabled in the calling service |
| Collector unhealthy | Check `http://localhost:13133/` and collector config syntax |
| Health check spans cluttering traces | Already filtered in `otel-collector-config.yaml` |

## Next Steps

- [ ] Add custom spans for business logic (shipping rate calculation, recommendation engine, notification dispatch)
- [ ] Add metrics signal (request rates, error rates, latency histograms)
- [ ] Add logs signal with trace correlation (Lograge + trace_id/span_id)
- [ ] Add Grafana Loki for centralized log aggregation
- [ ] Configure sampling for high-traffic production scenarios
- [ ] Add Grafana dashboards for service overview and RED metrics
