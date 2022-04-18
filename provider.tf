provider "aws" {
  profile    = "840706107855_AdministratorAccess"
  region     = var.region
}

provider "local" {}

provider "template" {}