import http from "k6/http";
import { check, sleep } from "k6";

// Replace with your ALB DNS name
const BASE_URL = __ENV.ALB_URL || "http://your-alb-dns-here";

export const options = {
  stages: [
    { duration: "30s", target: 10  },  // warm up
    { duration: "1m",  target: 50  },  // ramp up fast
    { duration: "2m",  target: 100 },  // heavy load — CPU should spike
    { duration: "2m",  target: 200 },  // brutal — errors expected, watch CPU max out
    { duration: "1m",  target: 0   },  // ramp down — watch tasks scale back in
  ],
  thresholds: {
    http_req_duration: ["p(95)<3000"], // 95% of requests under 3s
    http_req_failed:   ["rate<0.05"],  // less than 5% errors
  },
};

export default function () {
  const payload = JSON.stringify({
    urls: [
      "https://example.com",
      "https://httpbin.org/delay/1",
    ],
  });

  const res = http.post(`${BASE_URL}/jobs`, payload, {
    headers: { "Content-Type": "application/json" },
    timeout: "10s",
  });

  check(res, {
    "status 200": (r) => r.status === 200,
    "job completed": (r) => {
      try {
        return JSON.parse(r.body).status === "COMPLETED";
      } catch {
        return false;
      }
    },
  });

  sleep(0.2);  // 200ms pause — still hammers hard but avoids pure connection flood
}
