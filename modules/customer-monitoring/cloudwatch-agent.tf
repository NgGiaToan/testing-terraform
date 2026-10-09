# Attach the managed CloudWatch agent policy to the instance's existing IAM role
# (var.existing_ec2_role_name — created outside Terraform, already attached to the
# instance), plus the agent's config: memory and per-mount-point disk usage. CPU and
# network come from the hypervisor-level AWS/EC2 namespace and need no agent.

data "aws_iam_role" "existing_ec2" {
  count = local.instance_enabled ? 1 : 0
  name  = var.existing_ec2_role_name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = local.instance_enabled ? 1 : 0
  role       = data.aws_iam_role.existing_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# The agent reports disk_used_percent with path/device/fstype dimensions; the disk alarms
# in alarms-performance.tf must use the same values (var.mount_points).
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  count = local.instance_enabled ? 1 : 0
  name  = "/${var.environment}/cloudwatch-agent/config"
  type  = "String"
  tags  = local.common_tags

  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
    }
    metrics = {
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        disk = {
          measurement                 = ["disk_used_percent"]
          metrics_collection_interval = 60
          resources                   = [for m in values(var.mount_points) : m.path]
        }
      }
    }
  })
}
