#!/bin/bash
# Script to fix target groups with wrong target_type

echo "Removing target groups from Terraform state..."
terraform state rm 'module.ecs.aws_lb_target_group.tiles_tg' 2>/dev/null || echo "Tiles TG not in state"
terraform state rm 'module.ecs.aws_lb_target_group.timeseries_tg' 2>/dev/null || echo "Timeseries TG not in state"

echo "Removing ECS services from state (they depend on target groups)..."
terraform state rm 'module.ecs.aws_ecs_service.tiles' 2>/dev/null || echo "Tiles service not in state"
terraform state rm 'module.ecs.aws_ecs_service.timeseries' 2>/dev/null || echo "Timeseries service not in state"

echo "Removing Step Functions state machine from state..."
terraform state rm 'module.ingestion.aws_sfn_state_machine.ingestion' 2>/dev/null || echo "State machine not in state"

echo ""
echo "Now deleting the actual AWS resources..."
echo "Getting target group ARNs..."

TILES_TG_ARN=$(aws elbv2 describe-target-groups --names raster-app-prod-tiles-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
TS_TG_ARN=$(aws elbv2 describe-target-groups --names raster-app-prod-ts-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)

if [ "$TILES_TG_ARN" != "None" ] && [ -n "$TILES_TG_ARN" ]; then
  echo "Deleting tiles target group..."
  aws elbv2 delete-target-group --target-group-arn "$TILES_TG_ARN"
fi

if [ "$TS_TG_ARN" != "None" ] && [ -n "$TS_TG_ARN" ]; then
  echo "Deleting timeseries target group..."
  aws elbv2 delete-target-group --target-group-arn "$TS_TG_ARN"
fi

echo ""
echo "Done! Now run: terraform apply"
