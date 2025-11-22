resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(
    var.tags,
    { Name = "${var.name}-vpc" }
  )
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = merge(
    var.tags,
    { Name = "${var.name}-igw" }
  )
}

resource "aws_subnet" "public" {
  for_each                = { for idx, cidr in var.public_subnet_cidrs : idx => cidr }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = element(var.azs, tonumber(each.key))
  map_public_ip_on_launch = true
  tags = merge(
    var.tags,
    { Name = "${var.name}-public-${each.key}" }
  )
}

resource "aws_subnet" "private" {
  for_each          = { for idx, cidr in var.private_subnet_cidrs : idx => cidr }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = element(var.azs, tonumber(each.key))
  tags = merge(
    var.tags,
    { Name = "${var.name}-private-${each.key}" }
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-public-rt" }
  )
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(
    var.tags,
    { Name = "${var.name}-nat-eip" }
  )
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = merge(
    var.tags,
    { Name = "${var.name}-nat" }
  )
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-private-rt" }
  )
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  vpc_id      = aws_vpc.this.id
  description = "Allow HTTP(S) inbound"
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-alb-sg" }
  )
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name}-ecs-sg"
  vpc_id      = aws_vpc.this.id
  description = "Security group for ECS tasks"
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-ecs-sg" }
  )
}

resource "aws_security_group" "data" {
  name        = "${var.name}-data-sg"
  vpc_id      = aws_vpc.this.id
  description = "Security group for data services (OpenSearch, Redis)"
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-data-sg" }
  )
}

resource "aws_security_group" "dask" {
  name        = "${var.name}-dask-sg"
  vpc_id      = aws_vpc.this.id
  description = "Security group for Dask cluster"
  ingress {
    from_port       = 8786
    to_port         = 8787
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }
  ingress {
    from_port = 8786
    to_port   = 8787
    protocol  = "tcp"
    self      = true
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-dask-sg" }
  )
}

# VPC Endpoints
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags = merge(
    var.tags,
    { Name = "${var.name}-s3-endpoint" }
  )
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name}-vpc-endpoints-sg"
  vpc_id      = aws_vpc.this.id
  description = "Security group for VPC endpoints"
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(
    var.tags,
    { Name = "${var.name}-vpc-endpoints-sg" }
  )
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = merge(
    var.tags,
    { Name = "${var.name}-ecr-api-endpoint" }
  )
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = merge(
    var.tags,
    { Name = "${var.name}-ecr-dkr-endpoint" }
  )
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = merge(
    var.tags,
    { Name = "${var.name}-logs-endpoint" }
  )
}

resource "aws_vpc_endpoint" "opensearch" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.aos"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = merge(
    var.tags,
    { Name = "${var.name}-opensearch-endpoint" }
  )
}

output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "alb_security_group_id" { value = aws_security_group.alb.id }
output "ecs_tasks_security_group_id" { value = aws_security_group.ecs_tasks.id }
output "data_security_group_id" { value = aws_security_group.data.id }
output "dask_security_group_id" { value = aws_security_group.dask.id }