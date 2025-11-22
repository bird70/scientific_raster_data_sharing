resource "aws_ecr_repository" "repo" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  tags                 = var.tags
}

resource "aws_lb" "alb" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [var.alb_sg_id]
  tags               = var.tags
}

resource "aws_lb_target_group" "tiles_tg" {
  name     = "${var.name}-tiles-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path    = "/health"
    matcher = "200-399"
  }

  tags = var.tags
}

resource "aws_lb_target_group" "timeseries_tg" {
  name     = "${var.name}-ts-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path    = "/health"
    matcher = "200-399"
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "tiles_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tiles_tg.arn
  }

  condition {
    path_pattern {
      values = ["/tiles/*"]
    }
  }
}

resource "aws_lb_listener_rule" "timeseries_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.timeseries_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ECS cluster & task definitions
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-ecs-cluster"
  tags = var.tags
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "tiles" {
  name              = "/ecs/tiles-service"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "timeseries" {
  name              = "/ecs/timeseries-service"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "dask_scheduler" {
  name              = "/ecs/dask-scheduler"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "dask_workers" {
  name              = "/ecs/dask-workers"
  retention_in_days = 7
  tags              = var.tags
}

# ECS task definition for tiles service
resource "aws_ecs_task_definition" "tiles" {
  family                   = "tiles-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "tiles"
      image     = var.image_uri
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "S3_COG_PREFIX"
          value = "s3://${var.s3_cog_bucket}/"
        },
        {
          name  = "OPENSEARCH_HOST"
          value = var.opensearch_endpoint
        },
        {
          name  = "OPENSEARCH_INDEX"
          value = var.opensearch_index
        },
        {
          name  = "REDIS_URL"
          value = "redis://${var.redis_endpoint}:6379"
        },
        {
          name  = "COGNITO_JWKS_URL"
          value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}/.well-known/jwks.json"
        },
        {
          name  = "COGNITO_USERPOOL_AUD"
          value = var.cognito_client_id
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.tiles.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

# ECS task definition for timeseries service
resource "aws_ecs_task_definition" "timeseries" {
  family                   = "timeseries-service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "timeseries"
      image     = var.image_uri
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "S3_ZARR_PREFIX"
          value = "s3://${var.s3_zarr_bucket}/"
        },
        {
          name  = "OPENSEARCH_HOST"
          value = var.opensearch_endpoint
        },
        {
          name  = "OPENSEARCH_INDEX"
          value = var.opensearch_index
        },
        {
          name  = "REDIS_URL"
          value = "redis://${var.redis_endpoint}:6379"
        },
        {
          name  = "COGNITO_JWKS_URL"
          value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}/.well-known/jwks.json"
        },
        {
          name  = "COGNITO_USERPOOL_AUD"
          value = var.cognito_client_id
        },
        {
          name  = "DASK_SCHEDULER"
          value = var.dask_scheduler_endpoint != "" ? "${var.dask_scheduler_endpoint}:8786" : ""
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.timeseries.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

# ECS task definition for Dask scheduler
resource "aws_ecs_task_definition" "dask_scheduler" {
  family                   = "dask-scheduler"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "dask-scheduler"
      image     = "daskdev/dask:latest"
      essential = true
      command   = ["dask-scheduler"]
      portMappings = [
        {
          containerPort = 8786
          protocol      = "tcp"
        },
        {
          containerPort = 8787
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dask_scheduler.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

# ECS task definition for Dask workers
resource "aws_ecs_task_definition" "dask_workers" {
  family                   = "dask-workers"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"
  memory                   = "4096"
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "dask-worker"
      image     = "daskdev/dask:latest"
      essential = true
      command   = ["dask-worker"]
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "DASK_SCHEDULER_ADDRESS"
          value = var.dask_scheduler_endpoint != "" ? "tcp://${var.dask_scheduler_endpoint}:8786" : ""
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dask_workers.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = var.tags
}

# ECS service for tiles
resource "aws_ecs_service" "tiles" {
  name            = "tiles-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.tiles.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tiles_tg.arn
    container_name   = "tiles"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  tags = var.tags

  depends_on = [aws_lb_listener.https]
}

# ECS service for timeseries
resource "aws_ecs_service" "timeseries" {
  name            = "timeseries-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.timeseries.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.timeseries_tg.arn
    container_name   = "timeseries"
    container_port   = 8080
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  tags = var.tags

  depends_on = [aws_lb_listener.https]
}

# Autoscaling target for tiles service
resource "aws_appautoscaling_target" "tiles" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.tiles.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for tiles service
resource "aws_appautoscaling_policy" "tiles_cpu" {
  name               = "tiles-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.tiles.resource_id
  scalable_dimension = aws_appautoscaling_target.tiles.scalable_dimension
  service_namespace  = aws_appautoscaling_target.tiles.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Autoscaling target for timeseries service
resource "aws_appautoscaling_target" "timeseries" {
  max_capacity       = 20
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.timeseries.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for timeseries service
resource "aws_appautoscaling_policy" "timeseries_cpu" {
  name               = "timeseries-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.timeseries.resource_id
  scalable_dimension = aws_appautoscaling_target.timeseries.scalable_dimension
  service_namespace  = aws_appautoscaling_target.timeseries.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Cloud Map namespace for Dask service discovery
resource "aws_service_discovery_private_dns_namespace" "dask" {
  name        = "dask.local"
  vpc         = var.vpc_id
  description = "Private DNS namespace for Dask cluster"
  tags        = var.tags
}

resource "aws_service_discovery_service" "dask_scheduler" {
  name = "scheduler"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.dask.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = var.tags
}

# ECS service for Dask scheduler
resource "aws_ecs_service" "dask_scheduler" {
  name            = "dask-scheduler"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.dask_scheduler.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.dask_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.dask_scheduler.arn
  }

  tags = var.tags
}

# ECS service for Dask workers
resource "aws_ecs_service" "dask_workers" {
  name            = "dask-workers"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.dask_workers.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.dask_sg_id]
    assign_public_ip = false
  }

  tags = var.tags

  depends_on = [aws_ecs_service.dask_scheduler]
}

# Autoscaling target for Dask workers
resource "aws_appautoscaling_target" "dask_workers" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.dask_workers.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling policy for Dask workers
resource "aws_appautoscaling_policy" "dask_workers_cpu" {
  name               = "dask-workers-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dask_workers.resource_id
  scalable_dimension = aws_appautoscaling_target.dask_workers.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dask_workers.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
