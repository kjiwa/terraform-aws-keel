variable "name_prefix" {
  description = "Prefix for the Name tag on every hosted zone (string, lowercase letters, digits and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2 to 40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "domains" {
  description = "Apex domains to create hosted zones for (map of domain name to object). dnssec enables DNSSEC signing (KMS KSK + DS record) for that zone. A single-domain consumer passes one entry and reads zone_ids[<domain>]."
  type = map(object({
    dnssec = optional(bool, false)
  }))
}

variable "records" {
  description = "Extra records to create verbatim, such as ones carried over from a previous registrar (map of stable name to object). zone is a key of domains; ttl is in seconds; name is passed to Route 53 unchanged."
  type = map(object({
    zone   = string
    name   = string
    type   = string
    ttl    = optional(number, 300)
    values = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.records : contains(keys(var.domains), r.zone)])
    error_message = "Every records entry must name a zone that is a key of domains, because a record can only be created in a hosted zone this module manages."
  }
}

variable "dnssec_key_deletion_window_days" {
  description = "Days a DNSSEC KMS key stays pending after deletion is scheduled (number, 7 to 30)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.dnssec_key_deletion_window_days >= 7 && var.dnssec_key_deletion_window_days <= 30
    error_message = "dnssec_key_deletion_window_days must be between 7 and 30, the range KMS accepts."
  }
}
