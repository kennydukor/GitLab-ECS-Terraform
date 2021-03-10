terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "jeromedecoster"

    workspaces {
      name = "gitlab-ecs-terraform"
    }
  }
}
