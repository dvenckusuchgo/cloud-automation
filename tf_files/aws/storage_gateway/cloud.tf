# Inject credentials via the AWS_PROFILE environment variable and shared credentials file
# and/or EC2 metadata service
terraform {
  backend "s3" {
    encrypt = "true"
  }
}

# Inject credentials via the AWS_PROFILE environment variable and shared credentials file and/or EC2 metadata service
#
provider "aws" {}


resource "aws_instance" "storage-gw-server" {
  # Need to get the ami in var for now
  ami = "${var.ami_id}"
  instance_type = "m4.xlarge"
  associate_public_ip_address = false
  # Need to provide subnet in var for now
  subnet_id = "${var.subnet}"
  vpc_security_group_ids = ["${aws_security_group.storage-gateway-sg.id}"]
  root_block_device {
    # Get volume size from var permanently
    volume_size = "${var.size}"
    volume_type = "gp2"
    encrypted   = true
  }
  # add tags later
}

resource "aws_ebs_volume" "cache-disk" {
  availability_zone = "${aws_instance.storage-gw-server.availability_zone}"
  # Get volume size from var permanently
  size = "${var.cache_size}"
  encrypted = true
  type = "gp2"
  # add tags later
}

resource "aws_volume_attachment" "disk-attach" {
  device_name = "/dev/xvdb"
  volume_id = "${aws_ebs_volume.cache-disk.id}"
  instance_id = "${aws_instance.storage-gw-server.id}"
  force_detach = true
}

resource "aws_security_group" "storage-gateway-sg" {
  name = "storage-gateway-sg"
  vpc_id = "${local.vpcid}"
  # Add tags later
  ingress {
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "tcp"
    from_port = 20048
    to_port = 20048
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "udp"
    from_port = 20048
    to_port = 20048
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "tcp"
    from_port = 22
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "tcp"
    from_port = 111
    to_port = 111
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "udp"
    from_port = 111
    to_port = 111
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "tcp"
    from_port = 2049
    to_port = 2049
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol = "udp"
    from_port = 2049
    to_port = 2049
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "tcp"
    from_port = 0
    to_port = 65535
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "udp"
    from_port = 0
    to_port = 65535
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_storagegateway_gateway" "storage-gateway" {
  gateway_ip_address = "${aws_instance.storage-gw-server.private_ip}"
  gateway_name = "storage-gateway"
  gateway_timezone = "GMT"
  gateway_type = "FILE_S3"
}

data "aws_storagegateway_local_disk" "storage-gateway-data" {
  disk_path = "${aws_volume_attachment.disk-attach.device_name}"
  gateway_arn = "${aws_storagegateway_gateway.storage-gateway.arn}"
}

resource "aws_storagegateway_cache" "storage-gateway-cache" {
  disk_id = "${data.aws_storagegateway_local_disk.storage-gateway-data.id}"
  gateway_arn = "${aws_storagegateway_gateway.storage-gateway.arn}"
}

resource "aws_storagegateway_nfs_file_share" "nfs_share" {
  client_list = ["0.0.0.0/0"]
  gateway_arn = "${aws_storagegateway_gateway.storage-gateway.arn}"
  location_arn = "${aws_s3_bucket.transfer-bucket.arn}"
  role_arn = "${aws_iam_role.transfer-role.arn}"
}

resource "aws_iam_role" "transfer-role" {
  name = "transfer-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "storagegateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "transfer-policy-sg" {
  name = "transfer-policy-sg"
  description = "Allows access to storage gateway"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
    "Action": [
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads"
    ],
  # Make an s3 bucket for this and get name from it
    "Resource": "arn:aws:s3:::${aws_s3_bucket.transfer-bucket.bucket}",
    "Effect": "Allow"
  },
  {
    "Action": [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:GetObjectVersion",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ],
    "Resource": "arn:aws:s3:::${aws_s3_bucket.transfer-bucket.bucket}/*",
    "Effect": "Allow"
  }
  ]
}
EOF
}

resource "aws_iam_policy_attachment" "attach-policies" {
  name = "storageGW-attachment"
  roles = ["${aws_iam_role.transfer-role.name}"]
  policy_arn = "${aws_iam_policy.transfer-policy-sg.arn}"
}


resource "aws_s3_bucket" "transfer-bucket" {
  bucket = "test-gw-bucket"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}