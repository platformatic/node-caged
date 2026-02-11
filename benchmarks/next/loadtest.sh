#!/bin/bash

# E-commerce Load Test Script
# Tests: Node Standard, Node Caged, Watt Standard, Watt Caged via LoadBalancer URLs
# Realistic e-commerce scenarios: homepage, search, card details, game browsing, sellers

set -e

# Ensure LoadBalancer URLs are set
if [ -z "$URL_NODE_STANDARD" ] || [ -z "$URL_NODE_CAGED" ] || [ -z "$URL_WATT_STANDARD" ] || [ -z "$URL_WATT_CAGED" ]; then
  echo "Error: URL_NODE_STANDARD, URL_NODE_CAGED, URL_WATT_STANDARD, and URL_WATT_CAGED environment variables must be set"
  exit 1
fi

echo "========================================================================"
echo "E-COMMERCE LOAD TEST CONFIGURATION"
echo "========================================================================"
echo "URL_NODE_STANDARD: $URL_NODE_STANDARD"
echo "URL_NODE_CAGED:    $URL_NODE_CAGED"
echo "URL_WATT_STANDARD: $URL_WATT_STANDARD"
echo "URL_WATT_CAGED:    $URL_WATT_CAGED"
echo ""
echo "Test Parameters:"
echo "  - Initial NLB warm-up: 60s per endpoint (10->500 req/s ramp)"
echo "  - Pre-test warm-up: 20s per endpoint (50->400 req/s ramp)"
echo "  - Post-warmup wait: 60s before main test"
echo "  - Test duration: 60s ramp-up (0->400 req/s) + 120s @ 400 req/s"
echo "  - Cooldown: 480s between tests"
echo "  - Scenarios: Homepage, Search, Card Detail, Game Browse, Sellers"
echo "========================================================================"

# Pre-flight connectivity check
echo ""
echo "========================================================================"
echo "PRE-FLIGHT CONNECTIVITY CHECK"
echo "========================================================================"

check_endpoint() {
  local name=$1
  local url=$2
  local max_retries=30
  local retry_delay=10

  echo "Checking $name at $url..."
  echo "  Will retry up to $max_retries times with ${retry_delay}s delay..."

  for ((i=1; i<=max_retries; i++)); do
    local result=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>&1 || echo "000")

    if [[ "$result" == "200" ]]; then
      echo "  $name: OK (HTTP 200 on attempt $i)"
      return 0
    fi

    if [[ $i -lt $max_retries ]]; then
      echo "  Attempt $i/$max_retries: HTTP $result - retrying in ${retry_delay}s..."
      sleep $retry_delay
    fi
  done

  echo "  $name: FAILED after $max_retries attempts"
  echo "  Last response code: $result"
  echo "  Trying verbose curl for diagnostics:"
  curl -v --connect-timeout 10 --max-time 30 "$url" 2>&1 || true
  return 1
}

check_endpoint "Node Standard" "$URL_NODE_STANDARD/"
check_endpoint "Node Caged" "$URL_NODE_CAGED/"
check_endpoint "Watt Standard" "$URL_WATT_STANDARD/"
check_endpoint "Watt Caged" "$URL_WATT_CAGED/"

echo "========================================================================"

# Warm-up k6 script - gradual ramp to warm up NLB and connection pools
K6_WARMUP_SCRIPT=$(cat <<'EOF'
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    warmup: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 500,
      stages: [
        { duration: '15s', target: 100 },
        { duration: '15s', target: 300 },
        { duration: '15s', target: 500 },
        { duration: '15s', target: 500 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.1'],
  },
};

export default function () {
  const res = http.get(__ENV.TARGET, {
    timeout: "10s",
  });
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}
EOF
)

# Short k6 script for quick pre-test warm-up (after cooldown)
K6_QUICK_WARMUP=$(cat <<'EOF'
import http from 'k6/http';
export const options = {
  scenarios: {
    quick_warmup: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 300,
      stages: [
        { duration: '10s', target: 200 },
        { duration: '10s', target: 400 },
      ],
    },
  },
};
export default function () {
  http.get(__ENV.TARGET, { timeout: "5s" });
}
EOF
)

# E-commerce k6 test script - mixed realistic scenarios
K6_ECOMMERCE_SCRIPT=$(cat <<'EOF'
import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Custom metrics
const requestErrors = new Counter('request_errors');
const successfulRequests = new Counter('successful_requests');
const responseTime = new Trend('response_time_ms');

// Sample data for realistic requests
const SEARCH_QUERIES = ['pikachu', 'charizard', 'dragon', 'rare', 'ex', 'magic', 'yugioh'];
const GAME_SLUGS = ['pokemon', 'magic', 'yugioh', 'digimon', 'onepiece'];
const SET_SLUGS = ['scarlet-violet', 'paldea-evolved', 'murders-at-karlov-manor', 'phantom-nightmare'];

export const options = {
  scenarios: {
    mixed_load: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 5000,
      stages: [
        { duration: '60s', target: 400 },  // Ramp up over 60s
        { duration: '120s', target: 400 }, // Constant at 400 req/s for 120s
      ],
    },
  },
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};

// Helper to make request and track metrics
function makeRequest(url, name) {
  const start = Date.now();
  const res = http.get(url, { timeout: "10s", tags: { name: name } });
  const duration = Date.now() - start;

  responseTime.add(duration);

  if (res.status === 200) {
    successfulRequests.add(1);
  } else {
    requestErrors.add(1);
  }

  return res;
}

export default function () {
  const BASE = __ENV.TARGET;

  // Randomly select scenario (weighted distribution)
  const rand = Math.random();

  if (rand < 0.20) {
    // 20% - Homepage
    makeRequest(BASE + '/', 'homepage');
  } else if (rand < 0.45) {
    // 25% - Search with query
    const query = SEARCH_QUERIES[Math.floor(Math.random() * SEARCH_QUERIES.length)];
    const page = Math.floor(Math.random() * 5) + 1;
    makeRequest(BASE + '/search?q=' + query + '&page=' + page, 'search');
  } else if (rand < 0.65) {
    // 20% - Card detail (random card ID)
    const gameId = GAME_SLUGS[Math.floor(Math.random() * GAME_SLUGS.length)];
    const setNum = String(Math.floor(Math.random() * 10) + 1).padStart(2, '0');
    const cardNum = String(Math.floor(Math.random() * 200) + 1).padStart(3, '0');
    const cardId = gameId + '-set-' + setNum + '-' + cardNum;
    makeRequest(BASE + '/cards/' + cardId, 'card_detail');
  } else if (rand < 0.80) {
    // 15% - Game detail
    const gameSlug = GAME_SLUGS[Math.floor(Math.random() * GAME_SLUGS.length)];
    makeRequest(BASE + '/games/' + gameSlug, 'game_detail');
  } else if (rand < 0.90) {
    // 10% - Games list
    makeRequest(BASE + '/games', 'games_list');
  } else if (rand < 0.95) {
    // 5% - Sellers list
    makeRequest(BASE + '/sellers', 'sellers_list');
  } else {
    // 5% - Set detail (random set)
    const setSlug = SET_SLUGS[Math.floor(Math.random() * SET_SLUGS.length)];
    const page = Math.floor(Math.random() * 3) + 1;
    makeRequest(BASE + '/sets/' + setSlug + '?page=' + page, 'set_detail');
  }
}

import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

export function handleSummary(data) {
  const total = data.metrics.successful_requests.values.count + data.metrics.request_errors.values.count;
  const success = data.metrics.successful_requests.values.count;
  const errors = data.metrics.request_errors.values.count;
  const successRate = total > 0 ? ((success / total) * 100).toFixed(2) : 0;
  const rt = data.metrics.response_time_ms.values;

  const summary = [
    '',
    '========================================',
    'E-COMMERCE LOAD TEST SUMMARY',
    '========================================',
    'Total Requests:    ' + total,
    'Successful:        ' + success,
    'Errors:            ' + errors,
    'Success Rate:      ' + successRate + '%',
    '',
    'Response Times (ms):',
    '  Average:         ' + rt.avg.toFixed(2),
    '  Min:             ' + rt.min.toFixed(2),
    '  Median:          ' + rt.med.toFixed(2),
    '  Max:             ' + rt.max.toFixed(2),
    '  p(90):           ' + rt['p(90)'].toFixed(2),
    '  p(95):           ' + rt['p(95)'].toFixed(2),
    '  p(99):           ' + rt['p(99)'].toFixed(2),
    '========================================',
    '',
  ].join('\n');

  return {
    stdout: summary + '\n' + textSummary(data, { indent: '  ', enableColors: false }),
  };
}
EOF
)

# Function to warm up a single endpoint
warmup_endpoint() {
  local name=$1
  local url=$2

  echo ""
  echo "--- Warming up $name at $url ---"
  echo "  Ramping: 10 -> 100 -> 300 -> 500 req/s over 60s"
  echo "  Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  echo "$K6_WARMUP_SCRIPT" | k6 run --quiet --env TARGET="$url" - 2>&1 | tail -5

  echo "  Warmup completed at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "  Settling for 10s..."
  sleep 10
}

# Warm up ALL endpoints before any tests to ensure NLB is scaled
warmup_all_endpoints() {
  echo ""
  echo "========================================================================"
  echo "NLB WARM-UP PHASE"
  echo "========================================================================"
  echo "Warming up all endpoints to ensure NLB has scaled properly."
  echo "This prevents cold-start bias in benchmark results."
  echo ""

  warmup_endpoint "Node Standard" "$URL_NODE_STANDARD/"
  warmup_endpoint "Node Caged" "$URL_NODE_CAGED/"
  warmup_endpoint "Watt Standard" "$URL_WATT_STANDARD/"
  warmup_endpoint "Watt Caged" "$URL_WATT_CAGED/"

  echo ""
  echo "========================================================================"
  echo "NLB WARM-UP COMPLETE"
  echo "========================================================================"
  echo "All endpoints warmed up. Starting benchmark tests in 60s..."
  sleep 60
}

# Quick warm-up before each test (reconnect after cooldown)
quick_warmup() {
  local name=$1
  local url=$2

  echo ""
  echo "--- Quick warm-up: $name ---"
  echo "  Ramping 50 -> 400 req/s over 20s to re-establish connections"
  echo "$K6_QUICK_WARMUP" | k6 run --quiet --env TARGET="$url" - 2>&1 | tail -3
  echo "  Settling for 5s..."
  sleep 5
}

# Function to run e-commerce load test
run_ecommerce_test() {
  local name=$1
  local url=$2
  local test_num=$3

  echo ""
  echo "########################################################################"
  echo "TEST $test_num: $name"
  echo "URL: $url"
  echo "Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "########################################################################"

  # Show system stats before test
  echo ""
  echo "--- System Stats Before Test ---"
  free -h 2>/dev/null || true
  echo ""

  echo "Waiting 60s before main load test..."
  sleep 60

  echo ""
  echo "Starting main load test..."
  echo "$K6_ECOMMERCE_SCRIPT" | k6 run --quiet --log-output=none --env TARGET="$url" -

  local exit_code=$?

  echo ""
  echo "--- Test Completed ---"
  echo "Finished at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Exit code: $exit_code"

  # Show system stats after test
  echo ""
  echo "--- System Stats After Test ---"
  free -h 2>/dev/null || true
  echo ""

  return $exit_code
}

echo ""
echo "========================================================================"
echo "STARTING E-COMMERCE BENCHMARK TESTS"
echo "========================================================================"

# Warm up all endpoints first to ensure NLB is ready
warmup_all_endpoints

# Test 1: Node Standard
quick_warmup "Node Standard" "$URL_NODE_STANDARD/"
run_ecommerce_test "Node Standard" "$URL_NODE_STANDARD" 1

echo ""
echo "========================================================================"
echo "COOLDOWN: 480 seconds before next test"
echo "========================================================================"
sleep 480

# Test 2: Node Caged (pointer compression)
quick_warmup "Node Caged" "$URL_NODE_CAGED/"
run_ecommerce_test "Node Caged (pointer compression)" "$URL_NODE_CAGED" 2

echo ""
echo "========================================================================"
echo "COOLDOWN: 480 seconds before next test"
echo "========================================================================"
sleep 480

# Test 3: Watt Standard
quick_warmup "Watt Standard" "$URL_WATT_STANDARD/"
run_ecommerce_test "Watt Standard (2 workers)" "$URL_WATT_STANDARD" 3

echo ""
echo "========================================================================"
echo "COOLDOWN: 480 seconds before next test"
echo "========================================================================"
sleep 480

# Test 4: Watt Caged (pointer compression)
quick_warmup "Watt Caged" "$URL_WATT_CAGED/"
run_ecommerce_test "Watt Caged (2 workers, pointer compression)" "$URL_WATT_CAGED" 4

echo ""
echo "========================================================================"
echo "ALL E-COMMERCE TESTS COMPLETED"
echo "========================================================================"
