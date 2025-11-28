# Ingestion Pipeline Monitoring - Quick Reference

## Quick Start

### Deploy Monitoring
```bash
cd terraform
terraform apply
```

### Check Status
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 2 for success rate
# Select option 3 for execution time
```

## Key Metrics

| Metric | Target | Alarm Threshold |
|--------|--------|-----------------|
| Success Rate | >95% | <95% |
| Execution Time | 10-20 min | >20 min |
| CPU Utilization | 30-70% | N/A |
| Memory Utilization | 50-80% | >90% |
| Cost per File | ≤$0.02 | N/A |

## CloudWatch Alarms

| Alarm Name | Threshold | Action |
|------------|-----------|--------|
| `{project}-ingestion-high-failure-rate` | >2 failures in 5 min | Check logs |
| `{project}-ingestion-long-execution` | >20 minutes | Check resources |
| `{project}-zarr-task-failure` | Any failure | Check Zarr logs |
| `{project}-cog-task-failure` | Any failure | Check COG logs |
| `{project}-zarr-high-memory` | >90% for 10 min | Increase memory |
| `{project}-cog-high-memory` | >90% for 10 min | Increase memory |

## Quick Commands

### Check Recent Executions
```bash
aws stepfunctions list-executions \
  --state-machine-arn $(cd terraform && terraform output -raw ingestion_state_machine_arn) \
  --max-results 10 \
  --query 'executions[*].[name,status,startDate]' \
  --output table
```

### Check Success Rate (24h)
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 2
```

### View Logs
```bash
# Zarr conversion
aws logs tail /ecs/zarr-conversion --follow

# COG generation
aws logs tail /ecs/cog-generation --follow
```

### Check Costs (30 days)
```bash
./scripts/monitor-ingestion-pipeline.sh
# Select option 7
```

## Dashboard Access

**AWS Console:**
```
CloudWatch → Dashboards → {project_name}-ingestion-pipeline
```

**Direct URL:**
```
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name={project_name}-ingestion-pipeline
```

## Troubleshooting

### High Failure Rate
1. Check Step Functions: `aws stepfunctions list-executions --state-machine-arn <arn> --status-filter FAILED`
2. Check logs: `aws logs tail /ecs/zarr-conversion --filter-pattern ERROR`
3. Verify permissions: Check IAM roles

### Long Execution Time
1. Check resources: `./scripts/monitor-ingestion-pipeline.sh` → Option 4
2. Check file size: Review S3 object metadata
3. Increase CPU/Memory: Update task definition

### High Memory Usage
1. Check utilization: Dashboard or monitoring script
2. Increase memory: Update `terraform/modules/ecs/main.tf`
3. Redeploy: `terraform apply`

## Cost Verification

### Expected Costs
- **Lambda**: $5.02 per file
- **ECS**: $0.017 per file
- **Savings**: 98%

### Verify in Cost Explorer
1. AWS Console → Cost Management → Cost Explorer
2. Filter: Service = ECS, Step Functions
3. Group by: Tag (Project)
4. Compare: Current month vs previous month

## Monitoring Schedule

### Daily (First Month)
- [ ] Check dashboard
- [ ] Review alarms
- [ ] Verify success rate >95%

### Weekly (Ongoing)
- [ ] Review trends
- [ ] Check costs
- [ ] Review errors
- [ ] Optimize resources

### Monthly (Ongoing)
- [ ] Cost verification
- [ ] Performance analysis
- [ ] Capacity planning
- [ ] Update documentation

## Emergency Contacts

| Role | Contact | Response Time |
|------|---------|---------------|
| On-Call Engineer | __________ | <1 hour |
| Team Lead | __________ | <4 hours |
| AWS Support | __________ | Per contract |

## Rollback

If critical issues occur:

```bash
# 1. Disable ECS pipeline
aws s3api put-bucket-notification-configuration \
  --bucket <raw-bucket> \
  --notification-configuration file://rollback-config.json

# 2. Update Step Functions to use Lambda
# 3. Monitor for stability
```

## Support Resources

- **Full Documentation**: `docs/INGESTION_PIPELINE_MONITORING.md`
- **Deployment Checklist**: `docs/TASK_10_DEPLOYMENT_CHECKLIST.md`
- **Monitoring Script**: `scripts/monitor-ingestion-pipeline.sh`
- **AWS Documentation**: https://docs.aws.amazon.com/step-functions/
