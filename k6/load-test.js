import http from "k6/http";
import { check, sleep, group } from "k6";
import { Rate, Trend } from "k6/metrics";
import { browser } from "k6/browser";

// Custom metrics
const errorRate = new Rate("errors");
const storefrontDuration = new Trend("storefront_duration", true);
const apiDuration = new Trend("api_duration", true);
const proxyDuration = new Trend("proxy_duration", true);

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
    // API consumers hitting microservices directly
    api_calls: {
      executor: "constant-arrival-rate",
      rate: 10,
      timeUnit: "1s",
      duration: "2m",
      preAllocatedVUs: 10,
      exec: "hitApis",
    },
    // API consumers hitting microservices via the store (proxy)
    store_api_calls: {
      executor: "constant-arrival-rate",
      rate: 5,
      timeUnit: "1s",
      duration: "2m",
      preAllocatedVUs: 5,
      exec: "hitApisViaStore",
    },
    // Health checks — low frequency, ~1 every 10s
    health_checks: {
      executor: "constant-arrival-rate",
      rate: 1,
      timeUnit: "10s",
      duration: "2m",
      preAllocatedVUs: 1,
      exec: "checkHealth",
    },
    // Real browser users browsing the storefront
    browser_users: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "30s", target: 2 },
        { duration: "1m", target: 3 },
        { duration: "30s", target: 0 },
      ],
      exec: "browserJourney",
      options: {
        browser: { type: "chromium" },
      },
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
    [`${name} status 2xx`]: (r) => r.status >= 200 && r.status < 300,
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

  group("Product Listing", () => {
    const res = http.get(`${BASE_URL}/products`);
    storefrontDuration.add(res.timings.duration);
    checkResponse(res, "product listing");
  });

  sleep(0.5 + Math.random());

  group("Product Page", () => {
    const slug = pick(PRODUCT_SLUGS);
    const res = http.get(`${BASE_URL}/products/${slug}`);
    storefrontDuration.add(res.timings.duration);
    checkResponse(res, "product page");
  });

  sleep(0.5 + Math.random());

  group("Category Browse", () => {
    const categories = [
      "categories/canvas-prints",
      "categories/fine-art-prints",
      "categories/photo-prints",
      "categories/wall-art",
      "categories/miniatures",
    ];
    const res = http.get(`${BASE_URL}/t/${pick(categories)}`);
    storefrontDuration.add(res.timings.duration);
    check(res, { "category page loads": (r) => r.status === 200 || r.status === 302 });
  });

  sleep(1 + Math.random() * 2);
}

// --- Scenario: Hit microservice APIs -----------------------------------------
export function hitApis() {
  const scenario = Math.random();

  if (scenario < 0.35) {
    // Shipping rates
    group("Shipping API", () => {
      const payload = JSON.stringify({
        origin: {
          zip: "10001",
          city: "New York",
          state: "NY",
          country: "US",
        },
        destination: {
          zip: pick(["90001", "60601", "77001", "98101", "30301"]),
          city: "Los Angeles",
          state: "CA",
          country: "US",
        },
        package: {
          weight: Math.floor(Math.random() * 48) + 4,
          length: 12,
          width: 12,
          height: 2,
        },
      });
      const res = http.post(`${SHIPPING_URL}/api/v1/rates`, payload, {
        headers: { "Content-Type": "application/json" },
      });
      apiDuration.add(res.timings.duration);
      checkResponse(res, "shipping rates");
    });
  } else if (scenario < 0.6) {
    // Recommendations
    group("Recommendations API", () => {
      const productId = Math.floor(Math.random() * 32) + 1;
      const res = http.get(
        `${RECOMMENDATIONS_URL}/api/v1/recommendations?product_id=${productId}&limit=4`
      );
      apiDuration.add(res.timings.duration);
      checkResponse(res, "recommendations");
    });
  } else if (scenario < 0.8) {
    // Notifications - send
    group("Notifications API - Send", () => {
      const payload = JSON.stringify({
        notification: {
          type: pick(["order_confirmation", "shipping_update", "delivery_confirmation"]),
          recipient: `user${Math.floor(Math.random() * 100)}@example.com`,
          subject: "Load test notification",
          payload: { order_number: `R${Math.floor(Math.random() * 999999999)}` },
        },
      });
      const res = http.post(`${NOTIFICATIONS_URL}/api/v1/notifications`, payload, {
        headers: { "Content-Type": "application/json" },
      });
      apiDuration.add(res.timings.duration);
      checkResponse(res, "notification created");
    });
  } else {
    // Notifications - list recent
    group("Notifications API - List", () => {
      const res = http.get(
        `${NOTIFICATIONS_URL}/api/v1/notifications?limit=${Math.floor(Math.random() * 20) + 1}`
      );
      apiDuration.add(res.timings.duration);
      checkResponse(res, "notifications list");
    });
  }
}

// --- Scenario: Hit microservice APIs via the store (proxy) -------------------
export function hitApisViaStore() {
  const scenario = Math.random();

  if (scenario < 0.4) {
    // Shipping rates via store
    group("Store → Shipping", () => {
      const payload = JSON.stringify({
        origin: {
          zip: "10001",
          city: "New York",
          state: "NY",
          country: "US",
        },
        destination: {
          zip: pick(["90001", "60601", "77001", "98101", "30301"]),
          city: "Los Angeles",
          state: "CA",
          country: "US",
        },
        package: {
          weight: Math.floor(Math.random() * 48) + 4,
          length: 12,
          width: 12,
          height: 2,
        },
      });
      const res = http.post(`${BASE_URL}/api/v1/shipping/rates`, payload, {
        headers: { "Content-Type": "application/json" },
      });
      proxyDuration.add(res.timings.duration);
      checkResponse(res, "store→shipping");
    });
  } else if (scenario < 0.65) {
    // Recommendations via store
    group("Store → Recommendations", () => {
      const productId = Math.floor(Math.random() * 32) + 1;
      const res = http.get(
        `${BASE_URL}/api/v1/recommendations?product_id=${productId}&limit=4`
      );
      proxyDuration.add(res.timings.duration);
      checkResponse(res, "store→recommendations");
    });
  } else {
    // Notifications - send via store
    group("Store → Notifications", () => {
      const payload = JSON.stringify({
        notification: {
          type: pick(["order_confirmation", "shipping_update", "delivery_confirmation"]),
          recipient: `user${Math.floor(Math.random() * 100)}@example.com`,
          subject: "Load test notification",
          payload: { order_number: `R${Math.floor(Math.random() * 999999999)}` },
        },
      });
      const res = http.post(`${BASE_URL}/api/v1/notifications`, payload, {
        headers: { "Content-Type": "application/json" },
      });
      proxyDuration.add(res.timings.duration);
      checkResponse(res, "store→notification created");
    });
  }
}

// --- Scenario: Health checks (low frequency) ---------------------------------
export function checkHealth() {
  group("Health Checks", () => {
    const responses = http.batch([
      ["GET", `${BASE_URL}/up`],
      ["GET", `${SHIPPING_URL}/api/v1/health`],
      ["GET", `${RECOMMENDATIONS_URL}/api/v1/health`],
      ["GET", `${NOTIFICATIONS_URL}/api/v1/health`],
    ]);
    responses.forEach((res, i) => {
      const names = ["store", "shipping", "recommendations", "notifications"];
      checkResponse(res, `health-${names[i]}`);
    });
  });
}

// --- Scenario: Real browser user journey -------------------------------------
export async function browserJourney() {
  const page = await browser.newPage();

  try {
    // 1. Visit homepage
    await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
    check(await page.title(), {
      "browser: homepage loaded": (t) => t.length > 0,
    });

    await page.waitForTimeout(1000 + Math.random() * 2000);

    // 2. Click "Shop All" nav link to browse products
    const shopLink = page.locator('a[data-title="shop all"]').first();
    await Promise.all([
      page.waitForNavigation({ waitUntil: "networkidle" }),
      shopLink.click(),
    ]);
    check(page.url(), {
      "browser: navigated to products": (u) => u.includes("/products"),
    });

    await page.waitForTimeout(1000 + Math.random() * 2000);

    // 3. Click on a product from the listing
    const productLink = page.locator('a[href*="/products/"]').first();
    await Promise.all([
      page.waitForNavigation({ waitUntil: "networkidle" }),
      productLink.click(),
    ]);
    check(page.url(), {
      "browser: on product page": (u) => u.includes("/products/"),
    });

    await page.waitForTimeout(1000 + Math.random() * 1000);

    // 4. Try adding to cart if an "Add to Cart" button exists
    const addToCart = page.locator('button:has-text("Add to Cart"), input[value="Add to Cart"]').first();
    try {
      await addToCart.waitFor({ state: "visible", timeout: 3000 });
      await addToCart.click();
      await page.waitForTimeout(2000);
      check(true, { "browser: add to cart clicked": () => true });
    } catch {
      // Button may not exist or product may need variant selection — that's ok
    }

    await page.waitForTimeout(1000 + Math.random() * 1000);

    // 5. Browse a category page
    await page.goto(`${BASE_URL}/t/categories/canvas-prints`, { waitUntil: "networkidle" });
    check(page.url(), {
      "browser: category page loaded": (u) => u.includes("/t/categories/"),
    });

    await page.waitForTimeout(1000 + Math.random() * 2000);

    // 6. Navigate back to homepage
    await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
    check(await page.title(), {
      "browser: returned to homepage": (t) => t.length > 0,
    });
  } finally {
    await page.close();
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
