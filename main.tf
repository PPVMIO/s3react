provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
}

provider "null" {
  version = "~> 2.1"
}


resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.alias_name}.${var.domain_name}"
  acl    = "public-read"
  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "PublicReadGetObject",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::${var.alias_name}.${var.domain_name}/*"
      }
    ]
}
  EOF
  website {
    index_document = var.index_document
    error_document = var.error_document
  }
}


data "aws_s3_bucket" "thenewnormal_bucket" {
  bucket = aws_s3_bucket.website_bucket.bucket
}


data "aws_route53_zone" "hosted_zone" {
  name = "${var.domain_name}."
  private_zone = false
}

resource "aws_route53_record" "alias_record" {
  zone_id = data.aws_route53_zone.hosted_zone.id
  name    = var.alias_name
  type    = "A"

  alias {
    name    = replace(aws_cloudfront_distribution.s3_distribution.domain_name, "/[.]$/", "")
    zone_id = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_cloudfront_distribution.s3_distribution]

}

resource "aws_route53_record" "cert_validation_record" {
  name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.hosted_zone.id
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "${var.alias_name}.${var.domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation_record.fqdn]
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  enabled = true
  default_root_object = var.index_document
  aliases = ["${var.alias_name}.${var.domain_name}"]

  origin {
    domain_name = aws_s3_bucket.website_bucket.bucket_domain_name
    origin_id   = aws_cloudfront_origin_access_identity.access_identity.comment
  }


  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_cloudfront_origin_access_identity.access_identity.comment
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }



  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method = "sni-only"
  }

  depends_on = [aws_acm_certificate.cert]
}

resource "aws_cloudfront_origin_access_identity" "access_identity" {
  comment = "oai"
}
