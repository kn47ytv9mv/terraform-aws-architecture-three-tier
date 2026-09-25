variable "region" {
  default     = "us-east-1"
  description = "Region every resource in this architecture is created in."
}

variable "name" {
  default     = "three-tier"
  description = "Name prefix applied to every resource, so one account can hold several copies of this architecture without collision."
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "IPv4 range for the VPC. Each tier carves a /24 out of it per availability zone."
}

variable "availability_zone_count" {
  default     = 2
  description = "Availability zones to spread across. Two is the minimum for a Multi-AZ database and a load balancer AWS will accept."

  validation {
    condition     = var.availability_zone_count >= 2
    error_message = "This architecture needs at least two availability zones: an application load balancer requires subnets in two, and so does a Multi-AZ database."
  }
}

variable "instance_type" {
  default     = "t3.micro"
  description = "Instance type for the application tier."
}

variable "image_id" {
  default     = null
  description = "AMI the application tier boots from. Region-specific, so it has no default that would work everywhere."
}

variable "min_size" {
  default     = 2
  description = "Fewest application instances to run. Two keeps the tier alive through the loss of one availability zone."
}

variable "max_size" {
  default     = 6
  description = "Most application instances the group may scale to."
}

variable "database_engine" {
  default     = "postgres"
  description = "Database engine for the data tier."
}

variable "database_instance_class" {
  default     = "db.t4g.micro"
  description = "Compute and memory for the database instance."
}

variable "database_allocated_storage" {
  default     = 20
  description = "Storage allocated to the database, in gibibytes."
}

variable "cache_node_type" {
  default     = "cache.t4g.micro"
  description = "Node type for the cache tier."
}

variable "domain_name" {
  default     = null
  description = "Domain the architecture serves. Setting it creates a public hosted zone, an ACM certificate, and an alias record to the load balancer. If null, the load balancer's own DNS name is the only entry point."
}

variable "alarm_email" {
  default     = null
  description = "Address subscribed to the alarm topic. An email subscription stays pending until the recipient confirms it, so alarms deliver nothing until then."
}

variable "monthly_budget" {
  default     = null
  description = "Monthly spend in USD to alarm on, as a string. If null, no budget is created."
}

variable "tags" {
  default     = null
  description = "A map of tags applied to every resource in the architecture."
}
