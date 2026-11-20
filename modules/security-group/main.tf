locals {
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
  ingress_rules = flatten([
    for rule_index, rule in var.ingress_rules : [
      for cidr_index, cidr in rule.cidr_blocks : {
        key         = "${rule_index}-${cidr_index}"
        description = rule.description
        protocol    = rule.protocol
        from_port   = rule.from_port
        to_port     = rule.to_port
        cidr        = cidr
      }
    ]
  ])
}

resource "aws_security_group" "this" {
  name        = "${var.project_name}-${var.environment}-ec2"
  description = "Ingress for ${var.project_name} ${var.environment} instances"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-ec2"
  })
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = { for rule in local.ingress_rules : rule.key => rule }

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_ipv4         = each.value.cidr
}
