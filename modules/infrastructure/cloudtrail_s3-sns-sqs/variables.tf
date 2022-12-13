variable "cloudtrail_s3_name" {
  type        = string
  description = "Name of the Cloudtrail S3 bucket"
}

#---------------------------------
# optionals - with defaults
#---------------------------------

variable "s3_event_notification_filter_prefix" {
  type        = string
  default     = ""
  description = "S3 Path filter prefix for event notification. Limit the notifications to objects with key starting with specified characters"
}

variable "cloud_connector_cross_account_id" {
  type        = string
  description = "AWS Account Id, which need access to the sqs queue."
  default     = null
}

#
# general
#

variable "name" {
  type        = string
  description = "Name to be assigned to all child resources. A suffix may be added internally when required. Use default value unless you need to install multiple instances"
  default     = "sfc"
}


variable "tags" {
  type        = map(string)
  description = "customization of tags to be assigned to all resources. <br/>always include 'product' default tag for resource-group proper functioning.<br/>can also make use of the [provider-level `default-tags`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags)"
  default = {
    "product" = "sysdig-secure-for-cloud"
  }
}
