name                 = "raster-app-prod"
aws_region           = "ap-southeast-2"
alb_certificate_arn  = "arn:aws:acm:ap-southeast-2:123456789012:certificate/EXAMPLE"
domain_name          = "data.example.com"
cognito_user_pool_id = "ap-southeast-2_XXXXXXXXX"
enable_postgis       = false

# Tagging variables
project_owner = "platform-team"
project_title = "raster-timeseries-platform"
environment   = "prod"

# Cost Optimization Settings
# Reduce from 2 to 1 task per service to save ~$60/month
ecs_desired_count_tiles      = 1
ecs_desired_count_timeseries = 1