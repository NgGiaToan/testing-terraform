variable "unused_var" {
  default = "this variable is never used"
}

resource "aws_s3_bucket" "insecure" {
  bucket = "my-insecure-test-bucket-99999"
}

resource "aws_s3_bucket_public_access_block" "insecure_disabled" {
  bucket                  = aws_s3_bucket.insecure.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_iam_policy" "wide_open" {
  name = "wide-open-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_db_instance" "no_encryption" {
  identifier        = "test-db"
  engine            = "mysql"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  username          = "admin"
  password          = "SuperSecretPassword123!"
  storage_encrypted = false
  publicly_accessible = true
}
