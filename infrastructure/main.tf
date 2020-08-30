provider aws {
  profile = "default"
  region  = "us-east-1"
}

variable app_name {
  default = "ecs_app"  
}

variable task_version {
  default = 11
}


resource aws_vpc main {
  cidr_block = "172.31.0.0/16"
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_ecr_repository" "repo" {
  name                 = "${var.app_name}_repo"  
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

data aws_subnet_ids vpc_subnets {
  vpc_id = aws_vpc.main.id
}

data aws_subnet default_subnet {
  count = "${length(data.aws_subnet_ids.vpc_subnets.ids)}"
  id    = "${tolist(data.aws_subnet_ids.vpc_subnets.ids)[count.index]}"
}

data "aws_caller_identity" "current" {}

resource aws_lb_target_group lb_target_group {
  name        = "ecs-app-tg" 
  port        = 4000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id 
  target_type = "ip"
  health_check {
    path = "/health" 
    port = "4000"
  }
  stickiness {
    type            = "lb_cookie"
    enabled         = "true"
    cookie_duration = "3600"
  }
}

resource aws_lb_listener ecs_listener {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_target_group.arn
  }
}

resource aws_lb load_balancer {
  name               = "ecs-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_security_group.id]
  subnets            = data.aws_subnet.default_subnet.*.id

  enable_deletion_protection = false
}

resource aws_security_group lb_security_group {
  name        = "lb_security_group"
  description = "Allow all outbound traffic and https inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource aws_ecs_cluster ecs_cluster {
  name = "${var.app_name}_cluster"
}

resource aws_ecs_task_definition task_definition {
  family                    = "${var.app_name}_task"
  task_role_arn             = aws_iam_role.ecs_role.arn
  execution_role_arn        = aws_iam_role.ecs_execution_role.arn
  requires_compatibilities  = ["FARGATE"]
  memory                    = 8192
  cpu                       = 4096

  network_mode              = "awsvpc"

  container_definitions     = <<-EOF
  [
    {
      "cpu": 0,
      "image": "${aws_ecr_repository.repo.repository_url}:latest",
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.log_group.name}",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "portMappings": [
        {
          "hostPort": 4000,
          "protocol": "tcp",
          "containerPort": 4000
        }
      ],
      "environment": [],
      "mountPoints": [],
      "volumesFrom": [],
      "essential": true,
      "links": [],
      "name": "${var.app_name}"
    }
  ]
  EOF
}

resource aws_ecs_service service {
  name            = "${var.app_name}_service"
  cluster         = aws_ecs_cluster.ecs_cluster.id

  task_definition = "arn:aws:ecs:us-east-1:${data.aws_caller_identity.current.account_id}:task-definition/${aws_ecs_task_definition.task_definition.family}:${var.task_version}"
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    security_groups   = [aws_security_group.security_group.id]
    subnets           = data.aws_subnet.default_subnet.*.id
    assign_public_ip  = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.lb_target_group.arn
    container_name   = var.app_name
    container_port   = "4000"
  }

  service_registries {
    registry_arn =  aws_service_discovery_service.service_discovery.arn
    container_name = var.app_name 
  }
}

resource aws_security_group security_group {
  name        = var.app_name 
  description = "Allow all outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP/S Traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource aws_iam_role ecs_role {
  name = "ecs_role"
  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "",
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
}

resource aws_iam_role ecs_execution_role {
  name = "ecs_execution_role"
  assume_role_policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "",
        "Effect": "Allow",
        "Principal": {
          "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
}

resource aws_iam_policy ecs_policy {
  name = "ecs_policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Effect": "Allow",
          "Action": [
              "ecr:GetAuthorizationToken",
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "logs:CreateLogStream",
              "logs:PutLogEvents"
          ],
          "Resource": "*"
      }
  ]
}
EOF
}

resource aws_iam_policy_attachment attach_ecs_policy {
  name        = "attach-ecs-policy"
  roles       = [aws_iam_role.ecs_execution_role.name]
  policy_arn  = aws_iam_policy.ecs_policy.arn
}

resource aws_cloudwatch_log_group log_group {
  name = "/ecs/${var.app_name}"
}

resource "aws_service_discovery_private_dns_namespace" dns_namespace {
  name        = "${var.app_name}.local"
  description = "some desc"
  vpc         = aws_vpc.main.id
}

resource "aws_service_discovery_service" service_discovery {
  name = var.app_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.dns_namespace.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

output repo_url {
  value = aws_ecr_repository.repo.repository_url
}

output dns {
  value = aws_lb.load_balancer.dns_name
}
