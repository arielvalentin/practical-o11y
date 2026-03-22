import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend } from "k6/metrics";

// Custom metrics
const errorRate = new Rate("errors");
const storefrontDuration = new Trend("storefront_duration", true);
const apiDuration = new Trend("api_duration", true);

// --- Configuration -----------------------------------------------------------
const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const SHIPPING_URL = __ENV.SHIPPING_URL || "http://localhost:3001";
const RECOMMENDATIONS_URL = __ENV.RECOMMENDATIONS_URL || "http://localhost:3002";
const NOTIFICATIONS_URL = __ENV.NOTIFICATIONS_URL || "http://localhost:3003";

const PRODUCT_SLUGS = [
  "golden-hour-portrait",
  "studio-classic-headshot",
  "family-gathering-canvas",
  "moody-chiaroscuro-portrait",
  "child-s-first-portrait",
  "couple-s-embrace",
  "vintage-film-portrait",
  "ethereal-garden-portrait",
  "noir-portrait-series",
  "pet-portrait-classic",
  "modern-portrait-on-metal",
  "acrylic-face-mount-portrait",
  "rustic-wood-portrait",
  "wallet-portrait-set-8",
  "graduation-portrait",
  "wedding-portrait-panoramic",
  "executive-headshot-set",
  "maternity-portrait",
  "cityscape-self-portrait",
  "heritage-wood-portrait",
];

export const options = {
  scenarios: {
    // Browsing customers — steady load
    browse: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: "30s", target: 5 },
        { duration: "1m", target: 10 },
        { duration: "30s", target: 0 },
      ],
      exec: "browseStore",
    },
    // API consumers hitting microservices
    api_calls: {
      executor: "constant-arrival-rate",
      rate: 10,
      timeUnit: "1s",
      duration: "2m",
      preAllocatedVUs: 10,
      exec: "hitApis",
    },
  },
  thresholds: {
    http_req_duration: ["p(95)<2000"], // 95th percentile < 2s
    errors: ["rate<0.1"],              // error rate < 10%
  },
};

// --- Helpers -----------------------------------------------------------------
function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function checkResponse(res, name) {
  const ok = check(res, {
    [`${name} status 200`]: (r) => r.status === 200,
  });
  errorRate.add(!ok);
  return ok;
}

// --- Scenario: Browse the storefront -----------------------------------------
export function browseStore() {
  group("Homepage", () => {
    const res = http.get(`${BASE_URL}/`);
    storefrontDuration.add(res.timings.duration);
    checkResponse(res, "homepage");
  });

  sleep(1 + Math.random() * 2);

  group("Product Page", () => {
    const slug = pick(PRODUCT_SLUGS);
    const res = http.get(`${BASE_URL}/products/${slug}`);
    storefrontDuration.add(res.timings.duration);
    checkResponse(res, "product page");
  });

  sleep(0.5 + Math.random());

  group("Category Browse", () => {
    const categories = ["canvas-prints", "fine-art-prints", "photo-prints", "wall-art", "miniatures"];
    const res = http.get(`${BASE_URL}/t/${pick(categories)}`);
    storefrontDuration.add(res.timings.duration);
    check(res, { "category page loads": (r) => r.status === 200 || r.status === 302 });
  });

  sleep(1 + Math.random() * 2);
}

// --- Scenario: Hit microservice APIs -----------------------------------------
export function hitApis() {
  const scenario = Math.random();

  if (scenario < 0.4) {
    // Shipping rates
    group("Shipping API", () => {
      const payload = JSON.stringify({
        origin_zip: "10001",
        destination_zip: pick(["90001", "60601", "77001", "98101", "30301"]),
        weight_oz: Math.floor(Math.random() * 48) + 4,
        items: Math.floor(Math.random() * 5) + 1,
      });
      const res = http.post(`${SHIPPING_URL}/api/v1/rates`, payload, {
        headers: { "Content-Type": "application/json" },
      });
      apiDuration.add(res.timings.duration);
      checkResponse(res, "shipping rates");
    });
  } else if (scenario < 0.7) {
    // Recommendations
    group("Recommendations API", () => {
      const productId = Math.floor(Math.random() * 32) + 1;
      const res = http.get(
        `${RECOMMENDATIONS_URL}/api/v1/recommendations?product_id=${productId}&limit=4`
      );
      apiDuration.add(res.timings.duration);
      checkResponse(res, "recommendations");
    });
  } else if (scenario < 0.85) {
    // Notifications - send
    group("Notifications API - Send", () => {
      const payload = JSON.stringify({
        notification: {
          notification_type: pick(["order_confirmation", "shipping_update", "delivery_confirmation"]),
          recipient: `user${Math.floor(Math.random() * 100)}@example.com`,
          subject: "Load test notification",
          body: "This is a load test notification.",
          metadata: { order_number: `R${Math.floor(Math.random() * 999999999)}` },
        },
      });
      const res = http.post(`${NOTIFICATIONS_URL}/api/v1/notifications`, payload, {
        headers: { "Content-Type": "application/json" },
      });
      apiDuration.add(res.timings.duration);
      check(res, {
        "notification created": (r) => r.status === 200 || r.status === 201,
      });
    });
  } else {
    // Health checks across all services
    group("Health Checks", () => {
      const responses = http.batch([
        ["GET", `${SHIPPING_URL}/api/v1/health`],
        ["GET", `${RECOMMENDATIONS_URL}/api/v1/health`],
        ["GET", `${NOTIFICATIONS_URL}/api/v1/health`],
      ]);
      responses.forEach((res, i) => {
        apiDuration.add(res.timings.duration);
        checkResponse(res, `health-${i}`);
      });
    });
  }
}

// --- Summary -----------------------------------------------------------------
export function handleSummary(data) {
  const lines = [
    "\n========== Load Test Summary ==========",
    `Total requests:    ${data.metrics.http_reqs.values.count}`,
    `Failed requests:   ${data.metrics.http_req_failed?.values?.passes || 0}`,
    `Avg duration:      ${Math.round(data.metrics.http_req_duration.values.avg)}ms`,
    `P95 duration:      ${Math.round(data.metrics.http_req_duration.values["p(95)"])}ms`,
    `P99 duration:      ${Math.round(data.metrics.http_req_duration.values["p(99)"])}ms`,
    "=======================================\n",
  ];
  return {
    stdout: lines.join("\n"),
  };
}
