provider "aws" {
  region     = "ap-south-1"
  profile    = "shivanshk"
}

resource "aws_vpc" "task2_VPC" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true


  tags = {
    Name = "task_vpc"
  }
}

resource "aws_subnet" "alpha" {
  vpc_id            = aws_vpc.task2_VPC.id
  availability_zone = "ap-south-1a"
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.task2_VPC.id


  tags = {
    Name = "task_igw"
  }
}

resource "aws_route_table" "route" {
  vpc_id = aws_vpc.task2_VPC.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }


  tags = {
    Name = "task_routeTable"
  }
}

resource "aws_route_table_association" "route_asso" {
  subnet_id      = aws_subnet.alpha.id
  route_table_id = aws_route_table.route.id
}

resource "aws_security_group" "tcp" {
	name      = "terra"
  vpc_id    = aws_vpc.task2_VPC.id

	ingress { 
		from_port    = 80
		to_port      = 80 
		protocol     = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
	ingress { 
		from_port    = 22
		to_port      = 22
		protocol     = "tcp"
		cidr_blocks  = ["0.0.0.0/0"]
	}	

	egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
	
	tags = {
		Name = "allow_tcp"
	}
}


resource  "aws_instance"  "myins" {
	ami             = "ami-0732b62d310b80e97"
	instance_type   = "t2.micro"
	key_name        =  "cloudkey"
  vpc_security_group_ids = [ aws_security_group.tcp.id ]
	subnet_id       = aws_subnet.alpha.id

	connection {
    		type        = "ssh"
    		user        = "ec2-user"
   		private_key   = file("C:/Users/Shivansh Khandelwal/Downloads/cloudkey.pem")
    		host        = aws_instance.myins.public_ip
  	}


	provisioner "remote-exec" {
    		inline = [
      			"sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
      			"sudo systemctl start httpd",
      			"sudo systemctl enable httpd",
			
    		]
 	}		
		
	tags = {
		Name = "Task2"	
	}
}


resource "aws_efs_file_system" "efs" {
  depends_on = [
      aws_security_group.tcp
    ]
  creation_token = "my-product"

  tags = {
    Name = "EFS"
  }
}



resource "aws_efs_mount_target" "alpha" {
  depends_on = [ aws_efs_file_system.efs ]

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = aws_subnet.alpha.id
  security_groups = [ aws_security_group.tcp.id ]
}


resource "null_resource" "nullremote1"{

  depends_on = [ aws_efs_mount_target.alpha, ]

  connection {
        type        = "ssh"
        user        = "ec2-user"
      private_key   = file("C:/Users/Shivansh Khandelwal/Downloads/cloudkey.pem")
        host        = aws_instance.myins.public_ip
  }

	provisioner "remote-exec" {
		inline = [
      "sudo echo ${aws_efs_file_system.efs.dns_name}:/var/www/html efs default,_netdev 0 0 >> sudo /etc/fstab",
      "sudo mount ${aws_efs_file_system.efs.dns_name}:/ /var/www/html/",        
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Shivansh-sk/efs_task.git /var/www/html/"
    ]
	}
}


/*
resource "null_resource" "nulllocal2"{

	
	depends_on = [
		null_resource.nulllocal3,
	]
	

	provisioner "local-exec" {
		command = "chrome ${aws_instance.myins.public_ip}"
	}
}
*/


resource "aws_s3_bucket" "s3_bucket" {
	bucket = "sk1111"
	acl    = "public-read"

	tags   = {
		Name = "task2"
	}
	versioning{
		enabled = true
	}
}

locals {
		s3_origin_id = "mys3Origin"
}

resource "aws_s3_bucket_object" "upload" {

	depends_on =[aws_s3_bucket.s3_bucket]

	bucket 		 = "sk1111"
	key    		 = "dog"
	source 		 = "C:/Users/Shivansh Khandelwal/Desktop/dog.916.jpg"
	acl	 		   = "public-read"
	content_type = "image or jpeg"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = "sk1111.s3.amazonaws.com"
    prefix          = "myprefix"
  }


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

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

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}