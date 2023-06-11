terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.2.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}
# VPC
resource "aws_vpc" "test_vpc" {
  cidr_block = "10.1.0.0/16"
}

# TODO: variable.tf化
# TODO: module化 (Network, ECS, ALB)
# TODO:

# Public Subnets
resource "aws_subnet" "test_public_subnet_1" {
  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "test_public_subnet_2" {
  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "ap-northeast-1c"
}

# Private Subnets
resource "aws_subnet" "test_private_subnet_1" {
  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "test_private_subnet_2" {
  vpc_id            = aws_vpc.test_vpc.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "ap-northeast-1c"
}

# Internet Gateway
resource "aws_internet_gateway" "test_gw" {
  vpc_id = aws_vpc.test_vpc.id
}

# NAT Gateway
resource "aws_eip" "test_nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "test_nat_gw" {
  allocation_id = aws_eip.test_nat_eip.id
  subnet_id     = aws_subnet.test_public_subnet_1.id
}

# Route Tables
resource "aws_route_table" "test_public_route_table" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.test_gw.id
  }
}

resource "aws_route_table" "test_private_route_table" {
  vpc_id = aws_vpc.test_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.test_nat_gw.id
  }
}

# Associate subnets with the route tables
resource "aws_route_table_association" "test_public_a" {
  subnet_id      = aws_subnet.test_public_subnet_1.id
  route_table_id = aws_route_table.test_public_route_table.id
}

resource "aws_route_table_association" "test_public_b" {
  subnet_id      = aws_subnet.test_public_subnet_2.id
  route_table_id = aws_route_table.test_public_route_table.id
}

resource "aws_route_table_association" "test_private_a" {
  subnet_id      = aws_subnet.test_private_subnet_1.id
  route_table_id = aws_route_table.test_private_route_table.id
}

resource "aws_route_table_association" "test_private_b" {
  subnet_id      = aws_subnet.test_private_subnet_2.id
  route_table_id = aws_route_table.test_private_route_table.id
}


# Security Group for ECS tasks
resource "aws_security_group" "test_ecs_tasks_sg" {
  name   = "test_ecs_tasks_sg"
  vpc_id = aws_vpc.test_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.test_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for ALB
resource "aws_security_group" "test_alb_sg" {
  name   = "test_alb_sg"
  vpc_id = aws_vpc.test_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS cluster
resource "aws_ecs_cluster" "test_cluster" {
  name = "test-ecs-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "test_capacity_providers" {
  cluster_name       = aws_ecs_cluster.test_cluster.name
  capacity_providers = ["FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE_SPOT"
  }
}

# ECS task definition
resource "aws_ecs_task_definition" "test_taskdef" {
  family                   = "test-nginx-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  container_definitions    = <<TASK_DEFINITION
    [
      {
        "name": "nginx",
        "image": "nginx:latest",
        "memory": 512,
        "cpu": 256,
        "essential": true,
        "portMappings": [
          {
            "containerPort": 80,
            "hostPort": 80
          }
        ]
      }
    ]
    TASK_DEFINITION
}

# ECS service
resource "aws_ecs_service" "test_service" {
  name            = "test-nginx-service"
  cluster         = aws_ecs_cluster.test_cluster.id
  task_definition = aws_ecs_task_definition.test_taskdef.arn
  desired_count   = 2

  network_configuration {
    subnets          = [aws_subnet.test_private_subnet_1.id, aws_subnet.test_private_subnet_2.id]
    security_groups  = [aws_security_group.test_ecs_tasks_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.test_target_group.arn
    container_name   = "nginx"
    container_port   = 80
  }
}

# Load balancer
resource "aws_lb" "test_load_balancer" {
  name               = "test-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.test_alb_sg.id]
  subnets            = [aws_subnet.test_public_subnet_1.id, aws_subnet.test_public_subnet_2.id]
}

# Load balancer target group
resource "aws_lb_target_group" "test_target_group" {
  name        = "test-target-group"
  target_type = "ip"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.test_vpc.id
}

# Load balancer listener
resource "aws_lb_listener" "test_listener" {
  load_balancer_arn = aws_lb.test_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.test_target_group.arn
  }
}

# Output the DNS name of the load balancer
output "load_balancer_dns_name" {
  value = aws_lb.test_load_balancer.dns_name
}
