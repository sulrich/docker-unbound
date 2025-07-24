#!/bin/bash

echo "Running DNS tests..."

# Start unbound in the background
/unbound.sh &
UNBOUND_PID=$!

# Give unbound some time to start
sleep 5

# Test 1: Resolve a well-known domain (cloudflare.com)
echo "Testing resolution for cloudflare.com..."
drill @127.0.0.1 cloudflare.com || {
  echo "Test 1 failed: Could not resolve cloudflare.com"
  kill $UNBOUND_PID
  exit 1
}

echo "Test 1 passed: cloudflare.com resolved successfully."

# Test 2: Resolve another well-known domain (google.com)
echo "Testing resolution for google.com..."
drill @127.0.0.1 google.com || {
  echo "Test 2 failed: Could not resolve google.com"
  kill $UNBOUND_PID
  exit 1
}

echo "Test 2 passed: google.com resolved successfully."

# Add more tests as needed

echo "All DNS tests passed!"

kill $UNBOUND_PID
wait $UNBOUND_PID 2>/dev/null
