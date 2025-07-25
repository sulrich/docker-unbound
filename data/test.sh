#!/bin/bash

echo "running dns tests..."

# Start unbound in the background
/unbound.sh &
UNBOUND_PID=$!

# Give unbound some time to start
sleep 5

# test 1: resolve a well-known domain (cloudflare.com)
echo "Testing resolution for cloudflare.com..."
drill @127.0.0.1 cloudflare.com || {
  echo "test 1 failed: could not resolve cloudflare.com"
  kill $UNBOUND_PID
  exit 1
}

echo "test 1 passed: cloudflare.com resolved successfully."

# test 2: resolve another well-known domain (google.com)
echo "testing resolution for google.com..."
drill @127.0.0.1 google.com || {
  echo "test 2 failed: could not resolve google.com"
  kill $UNBOUND_PID
  exit 1
}

echo "test 2 passed: google.com resolved successfully."

# Add more tests as needed

echo "all dns tests passed!"

kill $UNBOUND_PID
wait $UNBOUND_PID 2>/dev/null
