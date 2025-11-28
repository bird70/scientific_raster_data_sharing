terraform {
  backend "s3" {
    bucket         = "cloud-scientific-raster-sharing-terraform-state-bucket"
    key            = "global/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}
