#!/bin/bash

# Test API Endpoints
set -e

# Get ALB URL (adjust if different)
ALB_URL="https://$(aws elbv2 describe-load-balancers --names "cloud-sciraster-alb" --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)"

if [[ "$ALB_URL" == "https://None" || "$ALB_URL" == "https://" ]]; then
    echo "❌ Could not find ALB DNS name"
    echo "Please check ALB exists: aws elbv2 describe-load-balancers"
    exit 1
fi

echo "🧪 Testing API endpoints..."
echo "Base URL: $ALB_URL"
echo "=========================="

# Test health endpoint
echo -e "\n1. Testing /health endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" "$ALB_URL/health" 2>/dev/null || echo -e "\nERROR")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Health check passed"
    echo "Response: $BODY"
else
    echo "❌ Health check failed (HTTP $HTTP_CODE)"
    echo "Response: $BODY"
fi

# Test root endpoint
echo -e "\n2. Testing / (root) endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" "$ALB_URL/" 2>/dev/null || echo -e "\nERROR")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Root endpoint passed"
else
    echo "❌ Root endpoint failed (HTTP $HTTP_CODE)"
fi

# Test docs endpoint
echo -e "\n3. Testing /docs endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" "$ALB_URL/docs" 2>/dev/null || echo -e "\nERROR")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Docs endpoint passed"
else
    echo "❌ Docs endpoint failed (HTTP $HTTP_CODE)"
fi

# Test collections endpoint
echo -e "\n4. Testing /api/collections endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" "$ALB_URL/api/collections" 2>/dev/null || echo -e "\nERROR")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Collections endpoint passed"
    echo "Response: $BODY"
else
    echo "❌ Collections endpoint failed (HTTP $HTTP_CODE)"
    echo "Response: $BODY"
fi

# Test timeseries endpoint (with sample data)
echo -e "\n5. Testing /api/timeseries endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" "$ALB_URL/api/timeseries?lon=150&lat=-33&start=2024-01-01T00:00:00Z&end=2024-01-31T23:59:59Z&variable=temperature" 2>/dev/null || echo -e "\nERROR")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Timeseries endpoint passed"
    echo "Response: $BODY"
else
    echo "❌ Timeseries endpoint failed (HTTP $HTTP_CODE)"
    echo "Response: $BODY"
fi

# Test metrics endpoint
echo -e "\n6. Testing /metrics endpoint..."
RESPONSE=$(curl -s -w "\n%{http_code}" "$ALB_URL/metrics" 2>/dev/null || echo -e "\nERROR")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Metrics endpoint passed"
else
    echo "❌ Metrics endpoint failed (HTTP $HTTP_CODE)"
fi

echo -e "\n=========================="
echo "🏁 Endpoint testing complete!"
echo ""
echo "If tests failed, check:"
echo "1. ECS services are running: aws ecs describe-services --cluster cloud-sciraster-ecs-cluster --services tiles-service timeseries-service"
echo "2. Target group health: aws elbv2 describe-target-health --target-group-arn <target-group-arn>"
echo "3. Security group rules allow ALB -> ECS communication"
echo "4. Task logs: aws logs tail /ecs/tiles-service --follow"