# Network Module

This module creates the VPC networking infrastructure including subnets, security groups, NAT gateway, and VPC endpoints for the Raster Time-series Access Web Service.

## Architecture

The module creates a multi-AZ VPC with:
- Public subnets for the Application Load Balancer
- Private subnets for ECS tasks, OpenSearch, and Redis
- NAT Gateway for outbound internet access from private subnets
- VPC endpoints for AWS services (S3, ECR, CloudWatch, OpenSearch)
- Security groups for ALB, ECS tasks, data services, and Dask cluster

## Components

### VPC and Subnets
- VPC with DNS support enabled
- Public subnets across multiple availability zones
- Private subnets across multiple availability zones
- Internet Gateway for public subnet internet access
- NAT Gateway for private subnet outbound access

### Security Groups

1. **ALB Security Group** (`alb-sg`)
   - Ingress: Port 443 from 0.0.0.0/0
   - Egress: All traffic to ECS security group

2. **ECS Tasks Security Group** (`ecs-sg`)
   - Ingress: Port 8080 from ALB security group
   - Egress: All traffic (for AWS service access)

3. **Data Security Group** (`data-sg`)
   - Ingress: Port 443 from ECS (OpenSearch)
   - Ingress: Port 6379 from ECS (Redis)
   - Egress: All traffic

4. **Dask Security Group** (`dask-sg`)
   - Ingress: Ports 8786-8787 from ECS
   - Ingress: Ports 8786-8787 from self (worker-to-scheduler)
   - Egress: All traffic

### VPC Endpoints

- **S3 Gateway Endpoint**: Cost-free gateway endpoint for S3 access
- **ECR API Interface Endpoint**: For pulling container images
- **ECR DKR Interface Endpoint**: For Docker registry operations
- **CloudWatch Logs Interface Endpoint**: For log streaming
- **OpenSearch Interface Endpoint**: For OpenSearch domain access

All interface endpoints use private DNS and are secured with a dedicated security group.

## Usage

```hcl
module "network" {
  source = "./modules/network"
  
  name                 = "raster-platform"
  cidr                 = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  azs                  = ["ap-southeast-2a", "ap-southeast-2b"]
  aws_region           = "ap-southeast-2"
  
  tags = {
    project_owner = "platform-team"
    project_title = "raster-platform"
    environment   = "production"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Name prefix for all resources | string | - | yes |
| cidr | CIDR block for VPC | string | - | yes |
| public_subnet_cidrs | CIDR blocks for public subnets | list(string) | - | yes |
| private_subnet_cidrs | CIDR blocks for private subnets | list(string) | - | yes |
| azs | Availability zones for subnets | list(string) | - | yes |
| aws_region | AWS region for VPC endpoints | string | - | yes |
| tags | Common tags to apply to all resources | map(string) | {} | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| public_subnet_ids | List of public subnet IDs |
| private_subnet_ids | List of private subnet IDs |
| alb_security_group_id | Security group ID for ALB |
| ecs_tasks_security_group_id | Security group ID for ECS tasks |
| data_security_group_id | Security group ID for data services |
| dask_security_group_id | Security group ID for Dask cluster |

## Security Considerations

- Private subnets have no direct internet access (NAT Gateway only)
- Security groups follow least-privilege principles
- VPC endpoints reduce data transfer costs and improve security
- All interface endpoints use private DNS for seamless integration

## Requirements

- Requirements 6.2: ECS tasks in private subnets
- Requirements 6.3: VPC endpoints for AWS services
- Requirements 9.6: Resource tagging
