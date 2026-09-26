terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # État distant dans le bucket créé par le bootstrap, verrouillage natif S3 (use_lockfile).
  # Paramètres dans backend.hcl (voir backend.hcl.example) : terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Projet        = "logiflow"
      Environnement = var.environnement
      GereePar      = "terraform"
      Depot         = "logiflow-infra"
    }
  }
}
