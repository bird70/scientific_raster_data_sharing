resource "aws_ecr_repository" "repo" {
  name = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
}

resource "aws_lb" "alb" {
  name = "${var.name}-alb"
  internal = false
  load_balancer_type = "application"
  subnets = var.public_subnets
  security_groups = [var.alb_sg_id]
}

resource "aws_lb_target_group" "tiles_tg" {
  name = "${var.name}-tiles-tg"
  port = 8080
  protocol = "HTTP"
  vpc_id = var.vpc_id
  health_check { path = "/health", matcher = "200-399" }
}

resource "aws_lb_target_group" "timeseries_tg" {
  name = "${var.name}-ts-tg"
  port = 8080
  protocol = "HTTP"
  vpc_id = var.vpc_id
  health_check { path = "/health", matcher = "200-399" }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port = 443
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = var.certificate_arn
  default_action { type = "fixed-response", fixed_response { content_type = "text/plain", message_body = "Not found", status_code = "404" } }
}

resource "aws_lb_listener_rule" "tiles_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority = 10
  action { type = "forward", target_group_arn = aws_lb_target_group.tiles_tg.arn }
  condition { path_pattern { values = ["/tiles/*"] } }
}

resource "aws_lb_listener_rule" "timeseries_rule" {
  listener_arn = aws_lb_listener.https.arn
  priority = 20
  action { type = "forward", target_group_arn = aws_lb_target_group.timeseries_tg.arn }
  condition { path_pattern { values = ["/api/*"] } }
}

# ECS cluster & task definitions
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-ecs-cluster"
}