resource "aws_route53_record" "this" {
  for_each = var.records

  zone_id = aws_route53_zone.this[each.value.zone].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
