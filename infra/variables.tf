variable "AWS_ACCESS_KEY_ID" {
  default = ""
  sensitive   = true
}

variable "AWS_SECRET_ACCESS_KEY" {
  default = ""
  sensitive   = true
}

variable "project_name" {
  default = "gitlab-ecs-terraform"
}

variable "region" {
  default = "eu-west-3"
}

variable "ecr_image" {
  default = ""
}

variable "desired_count" {
  default = 2
}
