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

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_internet_gateway.igw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private_assoc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public_assoc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.dask](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.ecs_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ecr_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.ecr_dkr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.opensearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region for VPC endpoints | `string` | n/a | yes |
| <a name="input_azs"></a> [azs](#input\_azs) | Availability zones for subnets | `list(string)` | n/a | yes |
| <a name="input_cidr"></a> [cidr](#input\_cidr) | CIDR block for VPC | `string` | n/a | yes |
| <a name="input_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#input\_private\_subnet\_cidrs) | CIDR blocks for private subnets | `list(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name prefix for all resources | `string` | n/a | yes |
| <a name="input_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#input\_public\_subnet\_cidrs) | CIDR blocks for public subnets | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Common tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_security_group_id"></a> [alb\_security\_group\_id](#output\_alb\_security\_group\_id) | n/a |
| <a name="output_dask_security_group_id"></a> [dask\_security\_group\_id](#output\_dask\_security\_group\_id) | n/a |
| <a name="output_data_security_group_id"></a> [data\_security\_group\_id](#output\_data\_security\_group\_id) | n/a |
| <a name="output_ecs_tasks_security_group_id"></a> [ecs\_tasks\_security\_group\_id](#output\_ecs\_tasks\_security\_group\_id) | n/a |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | n/a |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | n/a |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | n/a |
<!-- END_TF_DOCS -->