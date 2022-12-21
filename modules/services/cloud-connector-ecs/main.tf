data "aws_region" "current" {}

locals {
  verify_ssl = var.verify_ssl == "auto" ? length(regexall("https://.*?\\.sysdig(cloud)?.com/?", data.sysdig_secure_connection.current.secure_url)) == 1 : var.verify_ssl == "true"

  secure_api_token_secret = var.secure_api_token_secret_name != null ? var.secure_api_token_secret_name : local.secure_api_token_secret_arn

  secure_api_token_secret_arn = var.secure_api_token_secret_key_name != null ? "${var.secure_api_token_secret_arn}:${var.secure_api_token_secret_key_name}::" : var.secure_api_token_secret_arn
}
