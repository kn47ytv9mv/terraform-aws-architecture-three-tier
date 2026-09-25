module "network" {
  source  = "kn47ytv9mv/vpc/aws"
  version = "~> 1.0"

  vpc_cidr                = var.vpc_cidr
  availability_zone_count = var.availability_zone_count

  subnets = {
    public   = { public = true }
    app      = { nat_gateway_access = true }
    database = {}
  }

  gateway_endpoints = {
    s3 = {}
  }

  flow_logs = [
    {
      destination_arn  = module.flow_log_group.arn
      destination_type = "cloud-watch-logs"
    },
  ]

  tags = var.tags
}

module "flow_log_group" {
  source  = "kn47ytv9mv/cloudwatch-log-group/aws"
  version = "~> 1.0"

  name       = "/aws/vpc/${var.name}"
  kms_key_id = module.key.arn

  tags = var.tags
}

module "key" {
  source  = "kn47ytv9mv/kms-key/aws"
  version = "~> 1.0"

  description = "${var.name} architecture data key"

  tags = var.tags
}

module "key_alias" {
  source  = "kn47ytv9mv/kms-alias/aws"
  version = "~> 1.0"

  name          = var.name
  target_key_id = module.key.arn
}

module "log_bucket" {
  source  = "kn47ytv9mv/s3/aws"
  version = "~> 1.0"

  bucket = "${var.name}-logs"

  tags = var.tags
}

module "alb_security_group" {
  source  = "kn47ytv9mv/vpc-security-groups/aws"
  version = "~> 1.0"

  name        = "${var.name}-alb"
  vpc_id      = module.network.vpc_id
  description = "Public entry point for ${var.name}."

  ingress_rules = [
    { description = "HTTPS from the internet", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" },
    { description = "HTTP from the internet", ip_protocol = "tcp", from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" },
  ]

  egress_rules = [
    { description = "All outbound", ip_protocol = "-1", from_port = -1, to_port = -1, cidr_ipv4 = "0.0.0.0/0" },
  ]

  tags = var.tags
}

module "app_security_group" {
  source  = "kn47ytv9mv/vpc-security-groups/aws"
  version = "~> 1.0"

  name        = "${var.name}-app"
  vpc_id      = module.network.vpc_id
  description = "Application tier for ${var.name}, reachable only from the load balancer."

  ingress_rules = [
    { description = "From the load balancer", ip_protocol = "tcp", from_port = 8080, to_port = 8080, referenced_security_group_id = module.alb_security_group.id },
  ]

  egress_rules = [
    { description = "All outbound", ip_protocol = "-1", from_port = -1, to_port = -1, cidr_ipv4 = "0.0.0.0/0" },
  ]

  tags = var.tags
}

module "data_security_group" {
  source  = "kn47ytv9mv/vpc-security-groups/aws"
  version = "~> 1.0"

  name        = "${var.name}-data"
  vpc_id      = module.network.vpc_id
  description = "Data tier for ${var.name}, reachable only from the application tier."

  ingress_rules = [
    { description = "PostgreSQL from the application tier", ip_protocol = "tcp", from_port = 5432, to_port = 5432, referenced_security_group_id = module.app_security_group.id },
    { description = "Cache from the application tier", ip_protocol = "tcp", from_port = 6379, to_port = 6379, referenced_security_group_id = module.app_security_group.id },
  ]

  tags = var.tags
}

module "alb" {
  source  = "kn47ytv9mv/alb/aws"
  version = "~> 1.0"

  name               = "${var.name}-alb"
  internal           = false
  subnet_ids         = module.network.subnet_ids["public"]
  security_group_ids = [module.alb_security_group.id]

  access_logs_bucket = module.log_bucket.bucket
  access_logs_prefix = "alb"

  tags = var.tags
}

module "target_group" {
  source  = "kn47ytv9mv/alb-target-group/aws"
  version = "~> 1.0"

  name              = "${var.name}-app"
  vpc_id            = module.network.vpc_id
  port              = 8080
  protocol          = "HTTP"
  health_check_path = "/healthz"

  tags = var.tags
}

module "https_listener" {
  source  = "kn47ytv9mv/alb-listener/aws"
  version = "~> 1.0"

  load_balancer_arn = module.alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.domain_name != null ? module.certificate[0].arn : null
  target_group_arn  = module.target_group.arn

  tags = var.tags
}

module "http_redirect" {
  source  = "kn47ytv9mv/alb-listener/aws"
  version = "~> 1.0"

  load_balancer_arn = module.alb.arn
  port              = 80
  protocol          = "HTTP"
  type              = "redirect"

  redirect = {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }

  tags = var.tags
}

module "api_rule" {
  source  = "kn47ytv9mv/alb-listener-rule/aws"
  version = "~> 1.0"

  listener_arn     = module.https_listener.arn
  priority         = 100
  target_group_arn = module.target_group.arn
  path_patterns    = ["/api/*"]

  tags = var.tags
}

module "app_role" {
  source  = "kn47ytv9mv/iam-role/aws"
  version = "~> 1.0"

  name                  = "${var.name}-app"
  principal_identifiers = ["ec2.amazonaws.com"]
  managed_policy_arns   = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]

  tags = var.tags
}

module "launch_template" {
  source  = "kn47ytv9mv/launch-template/aws"
  version = "~> 1.0"

  name                   = "${var.name}-app"
  image_id               = var.image_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [module.app_security_group.id]

  block_device_mappings = [
    { device_name = "/dev/xvda", ebs = { volume_size = 20, volume_type = "gp3", kms_key_id = module.key.arn } },
  ]

  tag_specifications = [
    { resource_type = "instance", tags = { Name = "${var.name}-app" } },
  ]

  tags = var.tags
}

module "app_tier" {
  source  = "kn47ytv9mv/autoscaling-group/aws"
  version = "~> 1.0"

  name                = "${var.name}-app"
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = module.network.subnet_ids["app"]
  launch_template_id  = module.launch_template.id

  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = [module.target_group.arn]

  instance_refresh = {
    min_healthy_percentage = 90
    skip_matching          = true
  }

  instance_tags = { Name = "${var.name}-app" }
}

module "app_scaling" {
  source  = "kn47ytv9mv/autoscaling-policy/aws"
  version = "~> 1.0"

  name                   = "${var.name}-cpu"
  autoscaling_group_name = module.app_tier.name

  target_tracking = {
    target_value           = 60
    predefined_metric_type = "ASGAverageCPUUtilization"
  }

  estimated_instance_warmup = 300
}

module "db_subnets" {
  source  = "kn47ytv9mv/db-subnet-group/aws"
  version = "~> 1.0"

  name       = "${var.name}-database"
  subnet_ids = module.network.subnet_ids["database"]

  tags = var.tags
}

module "db_parameters" {
  source  = "kn47ytv9mv/db-parameter-group/aws"
  version = "~> 1.0"

  name   = "${var.name}-database"
  family = "postgres17"

  parameters = [
    { name = "log_connections", value = "1" },
  ]

  tags = var.tags
}

module "database" {
  source  = "kn47ytv9mv/db-instance/aws"
  version = "~> 1.0"

  identifier        = "${var.name}-database"
  engine            = var.database_engine
  instance_class    = var.database_instance_class
  allocated_storage = var.database_allocated_storage

  db_name                     = "app"
  username                    = "app"
  manage_master_user_password = true

  db_subnet_group_name   = module.db_subnets.name
  vpc_security_group_ids = [module.data_security_group.id]
  parameter_group_name   = module.db_parameters.name
  kms_key_id             = module.key.arn

  multi_az                            = true
  performance_insights_enabled        = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  final_snapshot_identifier           = "${var.name}-database-final"

  tags = var.tags
}

module "cache_subnets" {
  source  = "kn47ytv9mv/elasticache-subnet-group/aws"
  version = "~> 1.0"

  name       = "${var.name}-cache"
  subnet_ids = module.network.subnet_ids["database"]

  tags = var.tags
}

module "cache" {
  source  = "kn47ytv9mv/elasticache-replication-group/aws"
  version = "~> 1.0"

  replication_group_id = "${var.name}-cache"
  description          = "${var.name} session cache"

  engine             = "valkey"
  node_type          = var.cache_node_type
  num_cache_clusters = 2

  subnet_group_name  = module.cache_subnets.name
  security_group_ids = [module.data_security_group.id]
  kms_key_id         = module.key.arn

  tags = var.tags
}

module "app_secrets" {
  source  = "kn47ytv9mv/secretsmanager-secret/aws"
  version = "~> 1.0"

  name        = "${var.name}/app"
  description = "Application configuration for ${var.name}, read at runtime rather than passed as environment variables."
  kms_key_id  = module.key.arn

  tags = var.tags
}

module "certificate" {
  source  = "kn47ytv9mv/acm-certificate/aws"
  version = "~> 1.0"
  count   = var.domain_name != null ? 1 : 0

  domain_name = var.domain_name

  tags = var.tags
}

module "zone" {
  source  = "kn47ytv9mv/route53-zone/aws"
  version = "~> 1.0"
  count   = var.domain_name != null ? 1 : 0

  name = var.domain_name

  tags = var.tags
}

module "records" {
  source  = "kn47ytv9mv/route53-record/aws"
  version = "~> 1.0"
  count   = var.domain_name != null ? 1 : 0

  records = {
    apex = {
      zone_id = module.zone[0].id
      name    = var.domain_name
      type    = "A"

      alias = {
        name    = module.alb.dns_name
        zone_id = module.alb.zone_id
      }
    }
  }
}

module "alerts" {
  source  = "kn47ytv9mv/sns-topic/aws"
  version = "~> 1.0"

  name         = "${var.name}-alerts"
  display_name = "${var.name} alerts"

  subscriptions = var.alarm_email != null ? [
    { protocol = "email", endpoint = var.alarm_email },
  ] : []

  tags = var.tags
}

module "monitoring" {
  source  = "kn47ytv9mv/monitoring-baseline/aws"
  version = "~> 1.0"

  name_prefix   = var.name
  alarm_actions = [module.alerts.arn]
  ok_actions    = [module.alerts.arn]

  rds_instances = {
    app = { identifier = module.database.identifier }
  }

  load_balancers = {
    web = { arn_suffix = module.alb.arn_suffix }
  }

  autoscaling_groups = {
    app = { name = module.app_tier.name }
  }

  elasticache_replication_groups = {
    sessions = { replication_group_id = module.cache.replication_group_id }
  }

  tags = var.tags
}

module "backup_vault" {
  source  = "kn47ytv9mv/backup-vault/aws"
  version = "~> 1.0"

  name        = var.name
  kms_key_arn = module.key.arn

  tags = var.tags
}

module "backup_role" {
  source  = "kn47ytv9mv/iam-role/aws"
  version = "~> 1.0"

  name                  = "${var.name}-backup"
  principal_identifiers = ["backup.amazonaws.com"]
  managed_policy_arns   = ["arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"]

  tags = var.tags
}

module "backup_plan" {
  source  = "kn47ytv9mv/backup-plan/aws"
  version = "~> 1.0"

  name = var.name

  rules = [
    {
      rule_name         = "daily"
      target_vault_name = module.backup_vault.name
      schedule          = "cron(0 5 * * ? *)"
      lifecycle         = { delete_after = 35 }
    },
  ]

  selections = [
    {
      name         = "tagged"
      iam_role_arn = module.backup_role.arn
      resources    = ["*"]

      selection_tags = [
        { key = "Backup", value = "true" },
      ]
    },
  ]

  tags = var.tags
}

module "budget" {
  source  = "kn47ytv9mv/budget/aws"
  version = "~> 1.0"
  count   = var.monthly_budget != null ? 1 : 0

  name         = "${var.name}-monthly"
  limit_amount = var.monthly_budget

  notifications = [
    {
      threshold                 = 80
      notification_type         = "FORECASTED"
      subscriber_sns_topic_arns = [module.alerts.arn]
    },
  ]

  tags = var.tags
}

output "vpc_id" {
  description = "The ID of the VPC this architecture created."
  value       = module.network.vpc_id
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer — the architecture's entry point when no domain_name was supplied."
  value       = module.alb.dns_name
}

output "database_endpoint" {
  description = "Connection endpoint of the database, as host:port."
  value       = module.database.endpoint
}

output "database_secret" {
  description = "Secrets Manager secret AWS created and rotates for the database's master password."
  value       = module.database.master_user_secret
}

output "cache_primary_endpoint" {
  description = "Write endpoint of the cache."
  value       = module.cache.primary_endpoint_address
}

output "alerts_topic_arn" {
  description = "ARN of the topic every alarm in this architecture notifies."
  value       = module.alerts.arn
}

output "alarm_count" {
  description = "Number of CloudWatch alarms the monitoring baseline created."
  value       = module.monitoring.alarm_count
}

output "name_servers" {
  description = "Name servers for the hosted zone, to delegate the domain to. Empty when no domain_name was supplied."
  value       = var.domain_name != null ? module.zone[0].name_servers : []
}
