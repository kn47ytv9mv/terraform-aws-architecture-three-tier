mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

mock_provider "random" {}

run "a_single_availability_zone_is_rejected" {
  command = plan

  variables {
    availability_zone_count = 1
  }

  expect_failures = [var.availability_zone_count]
}

run "the_default_architecture_plans_and_wires_its_alarms_to_the_topic" {
  command = plan

  assert {
    condition     = module.monitoring.alarm_count == 10
    error_message = "The default architecture should alarm on its database, load balancer, autoscaling group, and cache."
  }

  assert {
    condition     = length(module.monitoring.alarm_names) == module.monitoring.alarm_count
    error_message = "Every alarm created should appear in the alarm_names output."
  }
}

run "no_domain_name_creates_no_dns_and_no_certificate" {
  command = plan

  assert {
    condition     = length(module.certificate) == 0
    error_message = "A certificate should only be created when a domain name is supplied."
  }

  assert {
    condition     = length(module.zone) == 0
    error_message = "A hosted zone should only be created when a domain name is supplied."
  }

  assert {
    condition     = length(module.records) == 0
    error_message = "An alias record should only be created when a domain name is supplied."
  }

  assert {
    condition     = length(output.name_servers) == 0
    error_message = "Without a hosted zone there are no name servers to delegate to."
  }
}

run "a_domain_name_creates_the_zone_certificate_and_record" {
  command = plan

  variables {
    domain_name = "example.com"
  }

  assert {
    condition     = length(module.certificate) == 1
    error_message = "Supplying a domain name should create a certificate for it."
  }

  assert {
    condition     = length(module.zone) == 1
    error_message = "Supplying a domain name should create a hosted zone for it."
  }

  assert {
    condition     = length(module.records) == 1
    error_message = "Supplying a domain name should create an alias record pointing at the load balancer."
  }
}

run "no_budget_amount_creates_no_budget" {
  command = plan

  assert {
    condition     = length(module.budget) == 0
    error_message = "A budget should only be created when a monthly amount is supplied."
  }
}

run "a_budget_amount_creates_a_budget_notifying_the_alarm_topic" {
  command = plan

  variables {
    monthly_budget = "500"
  }

  assert {
    condition     = length(module.budget) == 1
    error_message = "Supplying a monthly amount should create a budget."
  }
}

run "no_alarm_email_leaves_the_topic_without_subscribers" {
  command = plan

  assert {
    condition     = length(module.alerts.subscription_arns) == 0
    error_message = "Without an address the topic should have no subscriptions."
  }
}

run "an_alarm_email_subscribes_to_the_topic" {
  command = plan

  variables {
    alarm_email = "ops@example.com"
  }

  assert {
    condition     = length(module.alerts.subscription_arns) == 1
    error_message = "Supplying an address should subscribe it to the alarm topic."
  }
}
