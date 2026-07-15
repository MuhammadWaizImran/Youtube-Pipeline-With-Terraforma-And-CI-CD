# Log Analytics (replaces CloudWatch Logs) + Action Group (replaces the
# SNS topic + email subscription used by every Notify* state in the AWS
# Step Functions state machine).

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "alerts" {
  name                = "ag-${var.project}-${var.env}"
  resource_group_name = var.resource_group_name
  short_name          = substr("${var.project}${var.env}", 0, 12)

  email_receiver {
    name          = "pipeline-alerts"
    email_address = var.alert_email
  }

  tags = var.tags
}
