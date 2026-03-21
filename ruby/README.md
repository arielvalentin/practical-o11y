# Practical Observability — Ruby on Rails Demo

A multi-service ecommerce platform built with Ruby on Rails for demonstrating OpenTelemetry instrumentation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Compose                           │
│                                                                 │
│  ┌──────────────┐    HTTP     ┌──────────────────────┐         │
│  │              │────────────▶│  Shipping Service    │         │
│  │              │             │  :3001               │         │
│  │              │             │  POST /api/v1/rates   │         │
│  │              │             └──────────────────────┘         │
│  │              │                                               │
│  │    Spree     │    HTTP     ┌──────────────────────┐         │
│  │    Store     │────────────▶│  Recommendation Svc  │         │
│  │    :3000     │             │  :3002               │         │
│  │              │             │  GET /api/v1/recs     │         │
│  │              │             └──────────────────────┘         │
│  │              │                                               │
│  │              │    HTTP     ┌──────────────────────┐         │
│  │              │────────────▶│  Notification Svc    │         │
│  │              │             │  :3003               │         │
│  │              │             │  POST /api/v1/notifs  │         │
│  └──────┬───────┘             └──────────┬───────────┘         │
│         │                                │                      │
│         │         ┌──────────┐           │                      │
│         └────────▶│PostgreSQL│◀──────────┘                      │
│                   │  :5432   │                                   │
│                   └──────────┘                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| **Store** | 3000 | Main Spree Commerce app — storefront, admin, API |
| **Shipping** | 3001 | Mock shipping rate calculator (ground, express, overnight) |
| **Recommendations** | 3002 | Mock product recommendation engine |
| **Notifications** | 3003 | Email/notification dispatcher with DB persistence |
| **PostgreSQL** | 5432 | Shared database (separate DB per service) |

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
cd ruby
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

## Project Structure

```
ruby/
├── docker-compose.yml           # Orchestrates all services
├── init-databases.sql           # Creates databases on first run
├── store/                       # Spree Commerce (Rails full-stack)
│   ├── app/clients/             # HTTP clients for microservices
│   ├── app/subscribers/         # Spree event subscribers
│   └── ...
├── shipping-service/            # Rails API
│   ├── app/services/            # ShippingRateCalculator
│   └── ...
├── recommendation-service/      # Rails API
│   ├── app/services/            # RecommendationEngine
│   └── ...
└── notification-service/        # Rails API
    ├── app/services/            # NotificationDispatcher
    ├── app/models/              # Notification (persisted)
    └── ...
```

## Next Steps

- [ ] Add OpenTelemetry Ruby instrumentation to all services
- [ ] Add OTel Collector container to Docker Compose
- [ ] Add Jaeger or Grafana Tempo for trace visualization
- [ ] Configure trace propagation across HTTP boundaries
- [ ] Add custom spans for business logic
