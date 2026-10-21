resource "aws_route53_zone" "this" {
  for_each = var.domains
  name     = each.key

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}
