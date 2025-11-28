# Task 10: Production Deployment and Monitoring Checklist

## Overview

This checklist guides the gradual rollout of the ECS-based ingestion pipeline to production with comprehensive monitoring and cost verification.

## Pre-Deployment Checklist

- [ ] All previous tasks (1-9) completed successfully
- [ ] Integration tests passing
- [ ] Backward compatibility verified
- [ ] Terraform plan reviewed and approved
- [ ] SNS topic configured with correct email for alarms
- [ ] Team trained on new monitoring tools

## Phase 1: Infrastructure Deployment

### Deploy Monitoring Infrastructure

```bash
cd terraform
terraform plan
# Review the plan - should show new CloudWatch alarms and dashboard
terraform apply
```

**Expected Resources Created:**
- [ ] 6 CloudWatch alarms for ingestion pipeline
- [ ] 1 CloudWatch dashboard (`{project_name}-ingestion-pipeline`)
- [ ] SNS topic subscription confirmed (check email)

### Verify Deployment

```bash
# Check alarms are created
aws cloudwatch describe-alarms \
  --alarm-name-prefix "[YOURORG]-ingestion" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table

# Check dashboard exists
aws cloudwatch list-dashboards \
  --dashboard-name-prefix "[YOURORG]-ingestion" \
  --output table
```

**Verification:**
- [ ] All 6 alarms show "INSUFFICIENT_DATA" state (normal before first execution)
- [ ] Dashboard is accessible in AWS Console
- [ ] SNS email subscription confirmed

## Phase 2: 10% Traffic Rollout (Week 1)

### Enable Pipeline

The pipeline is already enabled via S3 event notifications. Monitor carefully during this phase.

### Daily Monitoring Tasks

**Day 1-7: Check these metrics daily**

```bash
# Run monitoring script
./scripts/monitor-ingestion-pipeline.sh
# Or on Windows:
# .\scripts\monitor-ingestion-pipeline.ps1

# Select options:
# 1. Show recent executions
# 2. Show success rate
# 3. Show execution time
# 4. Show Zarr task metrics
# 5. Show COG task metrics
```

**Daily Checklist:**
- [ ] Success rate > 95%
- [ ] Average execution time 10-20 minutes
- [ ] No critical alarms triggered
- [ ] CPU utilization 30-70%
- [ ] Memory utilization 50-80%
- [ ] No errors in CloudWatch Logs

### Week 1 Summary

**Metrics to Record:**
- Total files processed: _______
- Success rate: _______%
- Average execution time: _______ minutes
- Average CPU utilization: _______%
- Average memory utilization: _______%
- Number of failures: _______
- Cost per file: $_______

**Go/No-Go Decision for Phase 3:**
- [ ] Success rate ≥ 95%
- [ ] Execution time within 10-20 minutes
- [ ] No unresolved critical issues
- [ ] Team comfortable with monitoring tools
- [ ] Cost tracking shows expected savings

## Phase 3: 50% Traffic Rollout (Week 2)

### Continue Monitoring

Use the same daily monitoring tasks as Phase 2.

**Additional Checks:**
- [ ] Compare costs between Lambda and ECS in Cost Explorer
- [ ] Verify no increase in failure rate with higher volume
- [ ] Check for any resource contention issues

### Week 2 Summary

**Metrics to Record:**
- Total files processed: _______
- Success rate: _______%
- Average execution time: _______ minutes
- Average CPU utilization: _______%
- Average memory utilization: _______%
- Number of failures: _______
- Cost per file: $_______
- Estimated monthly cost: $_______

**Go/No-Go Decision for Phase 4:**
- [ ] Success rate ≥ 95%
- [ ] Performance consistent with Phase 2
- [ ] Cost savings confirmed (≥90% reduction)
- [ ] No operational issues
- [ ] Team confident in production readiness

## Phase 4: 100% Traffic Rollout (Week 3+)

### Full Production Deployment

All traffic is now routed through the ECS-based pipeline.

### Weekly Monitoring Tasks

**Week 3-6: Check these metrics weekly**

```bash
# Run monitoring script weekly
./scripts/monitor-ingestion-pipeline.sh

# Check all metrics:
# - Execution success rate
# - Execution time trends
# - Resource utilization
# - Cost estimation
```

**Weekly Checklist:**
- [ ] Success rate > 95%
- [ ] No degradation in performance
- [ ] Alarms functioning correctly
- [ ] Cost tracking shows sustained savings
- [ ] Team comfortable with operations

### Monthly Cost Verification

**Use AWS Cost Explorer:**

1. Navigate to: AWS Console → Cost Management → Cost Explorer
2. Filter by:
   - Service: ECS, Step Functions
   - Tag: Project = {project_name}
   - Date range: Last 30 days
3. Compare to previous month (Lambda-based)

**Expected Results:**
- Lambda costs: ~$5.02 per file
- ECS costs: ~$0.017 per file
- **Savings: 98%**

**Monthly Cost Checklist:**
- [ ] ECS costs within expected range
- [ ] Step Functions costs minimal (<$0.001 per execution)
- [ ] S3 costs unchanged
- [ ] Total ingestion cost reduced by ≥90%
- [ ] Cost anomaly detection configured

## Ongoing Monitoring

### Automated Monitoring

**CloudWatch Alarms (configured):**
- ✅ High failure rate (>2 failures in 5 min)
- ✅ Long execution time (>20 minutes)
- ✅ Zarr task failures
- ✅ COG task failures
- ✅ High memory usage (>90%)

**SNS Notifications:**
- All alarms send email to: ________________
- Response time SLA: < 1 hour for critical alarms

### Manual Monitoring Schedule

**Daily (first month):**
- Check dashboard for anomalies
- Review any alarm notifications
- Verify success rate > 95%

**Weekly (ongoing):**
- Review dashboard trends
- Check cost tracking
- Review error logs
- Optimize resource allocation if needed

**Monthly (ongoing):**
- Cost verification in Cost Explorer
- Performance trend analysis
- Capacity planning review
- Update documentation if needed

## Troubleshooting Guide

### High Failure Rate

**Symptoms:**
- Success rate < 95%
- Multiple alarm notifications

**Investigation Steps:**
1. Check Step Functions execution history
2. Review CloudWatch Logs for errors
3. Verify S3 permissions and file formats
4. Check ECS task resource allocation

**Common Causes:**
- Invalid NetCDF files
- S3 permission issues
- Memory exhaustion
- Network connectivity issues

### Long Execution Time

**Symptoms:**
- Execution time > 20 minutes
- Alarm notifications

**Investigation Steps:**
1. Check resource utilization (CPU/Memory)
2. Review file sizes being processed
3. Check S3 transfer speeds
4. Verify VPC endpoint configuration

**Common Causes:**
- Under-provisioned resources
- Large file sizes
- Network bottlenecks
- S3 throttling

### High Costs

**Symptoms:**
- Costs higher than expected
- Cost anomaly alerts

**Investigation Steps:**
1. Check execution frequency
2. Review task duration
3. Verify resource allocation
4. Check for stuck/long-running tasks

**Common Causes:**
- Over-provisioned resources
- Excessive retries
- Stuck executions
- Incorrect resource allocation

## Rollback Procedure

If critical issues arise:

### Immediate Rollback

```bash
# Disable ECS pipeline by removing S3 event notification
aws s3api put-bucket-notification-configuration \
  --bucket your-raw-bucket \
  --notification-configuration file://rollback-notification.json

# rollback-notification.json should configure Lambda-based trigger
```

### Re-enable Lambda Pipeline

1. Update Step Functions to use Lambda for Zarr conversion
2. Deploy Lambda functions
3. Monitor for stability
4. Investigate ECS issues offline

### Post-Rollback

- [ ] Document issues encountered
- [ ] Identify root cause
- [ ] Develop fix
- [ ] Test fix in non-production
- [ ] Plan re-deployment

## Success Criteria

### Technical Success

- [ ] Success rate ≥ 95% sustained for 30 days
- [ ] Average execution time 10-20 minutes
- [ ] No critical alarms for 7 consecutive days
- [ ] Resource utilization optimal (CPU 30-70%, Memory 50-80%)

### Cost Success

- [ ] Cost per file ≤ $0.02
- [ ] Total cost reduction ≥ 90% vs Lambda
- [ ] Monthly costs within budget
- [ ] Cost tracking automated

### Operational Success

- [ ] Team trained on monitoring tools
- [ ] Runbook documented and tested
- [ ] Alarm response procedures established
- [ ] No manual intervention required for normal operations

## Sign-Off

### Phase 1 (Infrastructure) - Completed: ___________
- Approved by: _________________ Date: _______

### Phase 2 (10% Traffic) - Completed: ___________
- Approved by: _________________ Date: _______

### Phase 3 (50% Traffic) - Completed: ___________
- Approved by: _________________ Date: _______

### Phase 4 (100% Traffic) - Completed: ___________
- Approved by: _________________ Date: _______

### Production Sign-Off - Completed: ___________
- Approved by: _________________ Date: _______

## Notes

Use this section to record any observations, issues, or lessons learned during deployment:

---

**Deployment Start Date:** ___________
**Deployment End Date:** ___________
**Total Duration:** ___________
**Final Success Rate:** _______%
**Final Cost per File:** $_______
**Total Cost Savings:** $_______
