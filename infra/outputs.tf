output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "ecr_image" {
  value = var.ecr_image
}
