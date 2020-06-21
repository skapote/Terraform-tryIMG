//Describing Provider
provider "aws" {
    region  = "ap-south-1"
    profile = "Sidproxy"
}

#Creating public & private key
resource "tls_private_key" "hci_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

#Creating public key
resource "aws_key_pair" "new_key" {
    key_name = "tf_task_key"
    public_key = tls_private_key.hci_key.public_key_openssh

    depends_on = [ tls_private_key.hci_key ]
}

#Creating private key
resource "local_file" "private_key" {
  content = tls_private_key.hci_key.private_key_pem
  filename = "terraform_key.pem"

  depends_on = [tls_private_key.hci_key]
}


#Creating security group- allowing ssh & http

resource "aws_security_group" "terraform_ssh_http" {
  name = "terraform_secure"
  description = "allowing ssh & http traffic"

  ingress {
          description = "ssh rule"
          from_port = 22
          to_port = 22
          protocol = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
  }
  

  ingress {
          description = "http rule"
          from_port = 80
          to_port = 80
          protocol = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
         from_port = 0
         to_port = 0
         protocol = "-1"
         cidr_blocks = ["0.0.0.0/0"]
  }
  
  
}
#Security group added

#Creating S3 bucket

resource "aws_s3_bucket" "terras3" {
  bucket = "terra-static-bucket"
  acl = "public-read"
  force_destroy = true
  depends_on = [aws_security_group.terraform_ssh_http]
  provisioner "local-exec" {
    command = "git clone https://github.com/skapote/appimage.git t1"
  }
}

#Adding objects into the Bucket

resource "aws_s3_bucket_object" "terra-object" {
    depends_on = [aws_s3_bucket.terras3]
  bucket = aws_s3_bucket.terras3.bucket
  key = "Geneva.jpg"
  source = "/Users/Manasi/Downloads/Geneva.jpg"
  acl = "public-read"
}

#Creating CloudFront using S3 bucket

resource "aws_cloudfront_distribution" "cloudy-sky" {
  origin {
  domain_name = "${aws_s3_bucket.terras3.bucket_regional_domain_name}"
  origin_id = "${aws_s3_bucket.terras3.id}"

}


enabled          = true
is_ipv6_enabled  = true
comment          = "Distribution"


default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${aws_s3_bucket.terras3.id}"

    forwarded_values {
       query_string = false

    cookies {
       forward = "none"
    }
}

viewer_protocol_policy = "allow-all"
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
}

restrictions {
    geo_restriction {
      restriction_type = "none"
    }
}    

tags = {
     Name   = "CloudFront_distribution"
     Environment  = "Production"
}

viewer_certificate {
    cloudfront_default_certificate = true
}


depends_on = [ aws_s3_bucket.terras3 ]
}

#Launching an EC2 Instance

resource "aws_instance" "application" {
ami           = "ami-0447a12f28fddb066"
instance_type = "t2.micro"
key_name      = "${aws_key_pair.new_key.key_name}"
security_groups = [ "terraform_secure" ]

connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.hci_key.private_key_pem
    host     = aws_instance.application.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"   
 ]
  }


#tagging

tags = {
  Name = "terra_app"
  env  = "Production"
}

depends_on = [
    aws_security_group.terraform_ssh_http,
    aws_key_pair.new_key
 ]
}

#Creating EBS Volume

resource "aws_ebs_volume" "app_storage" {
  depends_on       = [ aws_instance.application ]
  availability_zone = aws_instance.application.availability_zone
  size             = 1
    
    tags = {
       Name = "storage_drive"
    }
}

#Attaching ebs volume 

resource "aws_volume_attachment" "added_storage" {
  depends_on = [aws_ebs_volume.app_storage]
  device_name = "/dev/sdh"
  volume_id = "${aws_ebs_volume.app_storage.id}"
  instance_id = "${aws_instance.application.id}"
  force_detach = true
}

#Creating null resource

resource "null_resource" "null_mount" {
  depends_on = [aws_volume_attachment.added_storage]
  connection {
      type   = "ssh"
      user   = "ec2-user"
      private_key = tls_private_key.hci_key.private_key_pem
      host        = aws_instance.application.public_ip
  }

provisioner "remote-exec" {
  inline = [
  "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/skapote/Terraform-tryIMG.git  /var/www/html",
      ]
}

}

resource "null_resource" "wrap_up" {
  depends_on = [null_resource.null_mount]
  provisioner "local-exec" {
  command = "echo Task 1 Completed >> result.txt"
  }
}

resource "null_resource" "web_run" {
  depends_on = [null_resource.wrap_up]
  provisioner "local-exec" {
  command = "open -a \"google chrome\" http://${aws_instance.application.public_ip}"
  }
}
