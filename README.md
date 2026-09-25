# terraform-aws-architecture-three-tier

Terraform module for a complete three-tier web architecture — a public
load balancer, a private autoscaling application tier, and a private
data tier — assembled from this family's single-purpose modules.

## Cost

This is the most expensive kind of module in this family, because it
stands up running infrastructure rather than configuration. At the
defaults, the standing charges are two NAT gateways (one per
availability zone), a Multi-AZ `db.t4g.micro` database, two
`cache.t4g.micro` cache nodes, two `t3.micro` application instances, an
application load balancer, and ten CloudWatch alarms. Nothing here is
free-tier. Destroy it when you are finished with it, and set
`monthly_budget` so a forecast overrun reaches you.

The single largest saving available is `availability_zone_count = 2`
rather than 3, which this module already defaults to — each added zone
adds a NAT gateway and its data processing charges.

## Design

Every resource comes from a published module in this family, resolved
from the Terraform Registry under a `~> 1.0` version constraint. This
module contains no `resource` blocks of its own; it is wiring and
nothing else. Read any individual module's README to
understand what it creates and why its defaults are what they are.

### What it builds

| Tier | Contents |
|---|---|
| Network | VPC across `availability_zone_count` zones, public, application, and database subnets, an S3 gateway endpoint, and flow logs to CloudWatch |
| Public | Internet-facing application load balancer, HTTPS listener, HTTP-to-HTTPS redirect, access logs to S3 |
| Application | Launch template and autoscaling group in the private subnets, target-tracking CPU scaling, instance profile for SSM |
| Data | Multi-AZ PostgreSQL instance and a two-node Valkey replication group, both in the database subnets |
| Cross-cutting | Customer managed KMS key, Secrets Manager secret, SNS alarm topic, ten CloudWatch alarms, daily AWS Backup plan, optional budget |

The three security groups form a chain: the internet reaches only the
load balancer, the load balancer reaches only the application tier on
port 8080, and the application tier reaches only the data tier on 5432
and 6379. Nothing in the application or data tier is reachable from the
internet, and neither has a public IP.

### Where a domain fits

`domain_name` is optional, and it changes the shape of what is built.
Left null, the architecture's entry point is the load balancer's own
`*.elb.amazonaws.com` name and no certificate is issued — useful for a
staging environment nobody types a URL for. Set, it additionally creates
a public hosted zone, an ACM certificate, and an alias record at the
apex pointing to the load balancer.

**Setting `domain_name` does not finish the job.** A newly created
hosted zone is not authoritative for the domain until the registrar is
pointed at it, and ACM cannot validate the certificate until it is. Take
the `name_servers` output to the registrar; until you do, the apply will
wait on certificate validation and eventually time out.

### Things it deliberately does not do

Four Trivy findings survive on this configuration by design, and they
are worth stating rather than silently suppressing:

- **Unrestricted egress** on the load balancer and application security
  groups. An application tier that cannot reach the internet cannot
  install packages, call a third-party API, or reach an AWS service
  without a VPC endpoint for it. Narrow this once you know what the
  workload actually talks to.
- **An internet-facing load balancer.** That is the point of the public
  tier. Set `internal = true` on the `alb` module for an architecture
  fronted by something else.
- **No access logging on the log bucket.** The bucket that receives the
  load balancer's access logs does not log access to itself.
- **`deletion_protection` off on the database.** Enabling it makes
  `terraform destroy` fail until a separate apply turns it off again,
  which is hostile for an architecture people stand up to evaluate.
  Turn it on for anything you intend to keep.

`image_id` has no default, because AMI IDs are region-specific and any
default would be wrong in most regions. Supply one for the region you
are deploying into.

## Usage

```hcl
module "staging" {
  source  = "kn47ytv9mv/architecture-three-tier/aws"
  version = "~> 1.0"

  name     = "staging"
  image_id = "ami-0123456789abcdef0"

  alarm_email = "ops@example.com"
}
```

A production environment across three availability zones, with a domain
and a budget:

```hcl
module "production" {
  source = "github.com/kn47ytv9mv/terraform-aws-architecture-three-tier"

  name                    = "production"
  region                  = "us-east-1"
  availability_zone_count = 3

  image_id      = "ami-0123456789abcdef0"
  instance_type = "m7g.large"
  min_size      = 3
  max_size      = 12

  database_instance_class    = "db.r7g.large"
  database_allocated_storage = 200
  cache_node_type            = "cache.r7g.large"

  domain_name    = "example.com"
  alarm_email    = "ops@example.com"
  monthly_budget = "2000"

  tags = {
    Environment = "production"
    Backup      = "true"
  }
}
```

The `Backup` tag in that example is not decorative — the backup plan
selects resources by `Backup = "true"`, so anything without it is
created but never backed up.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| region | Region every resource in this architecture is created in. | `"us-east-1"` | no |
| name | Name prefix applied to every resource, so one account can hold several copies of this architecture without collision. | `"three-tier"` | no |
| vpc_cidr | IPv4 range for the VPC. Each tier carves a /24 out of it per availability zone. | `"10.0.0.0/16"` | no |
| availability_zone_count | Availability zones to spread across. Two is the minimum for a Multi-AZ database and a load balancer AWS will accept. | `2` | no |
| instance_type | Instance type for the application tier. | `"t3.micro"` | no |
| image_id | AMI the application tier boots from. Region-specific, so it has no default that would work everywhere. | `null` | no |
| min_size | Fewest application instances to run. Two keeps the tier alive through the loss of one availability zone. | `2` | no |
| max_size | Most application instances the group may scale to. | `6` | no |
| database_engine | Database engine for the data tier. | `"postgres"` | no |
| database_instance_class | Compute and memory for the database instance. | `"db.t4g.micro"` | no |
| database_allocated_storage | Storage allocated to the database, in gibibytes. | `20` | no |
| cache_node_type | Node type for the cache tier. | `"cache.t4g.micro"` | no |
| domain_name | Domain the architecture serves. Setting it creates a public hosted zone, an ACM certificate, and an alias record to the load balancer. If null, the load balancer's own DNS name is the only entry point. | `null` | no |
| alarm_email | Address subscribed to the alarm topic. An email subscription stays pending until the recipient confirms it, so alarms deliver nothing until then. | `null` | no |
| monthly_budget | Monthly spend in USD to alarm on, as a string. If null, no budget is created. | `null` | no |
| tags | A map of tags applied to every resource in the architecture. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| vpc_id | The ID of the VPC this architecture created. |
| load_balancer_dns_name | DNS name of the load balancer — the architecture's entry point when no `domain_name` was supplied. |
| database_endpoint | Connection endpoint of the database, as `host:port`. |
| database_secret | Secrets Manager secret AWS created and rotates for the database's master password. |
| cache_primary_endpoint | Write endpoint of the cache. |
| alerts_topic_arn | ARN of the topic every alarm in this architecture notifies. |
| alarm_count | Number of CloudWatch alarms the monitoring baseline created. |
| name_servers | Name servers for the hosted zone, to delegate the domain to. Empty when no `domain_name` was supplied. |

## License

MIT — see [LICENSE.md](LICENSE.md).
