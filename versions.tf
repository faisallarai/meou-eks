terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.62.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.2.2"
    }

    template = {
      source  = "hashicorp/template"
      version = "~> 2.2.0"
    }
  }

  backend "s3" {
    bucket         = "demo-meuo"
    dynamodb_table = "demo-meuo-locks"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    profile        = "840706107855_AdministratorAccess"
  }

}