provider "aws" {
  region = "us-east-1"  
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "rds" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "grafana" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOURIP/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_db_instance" "postgres" {
  allocated_storage      = 20
  storage_type          = "gp2"
  engine                = "postgres"
  engine_version        = "17.2"
  instance_class        = "db.t3.micro"
  username             = "dbadmin"
  password             = random_password.db_password.result
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name = aws_db_subnet_group.main.name
  publicly_accessible  = false
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "AWSDB_key"
  public_key = file("/Users/YOURDIR/.ssh/id_YOURKEY.pub")
}

resource "aws_instance" "grafana" {
  ami           = "ami-0fc5d935ebf8bc3bc" # Ubuntu 24.04 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.grafana.id]
  key_name       = aws_key_pair.ec2_key.key_name

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              apt update && apt install -y postgresql-client
              
              until PGPASSWORD=${random_password.db_password.result} psql -h ${replace(aws_db_instance.postgres.endpoint, ":5432", "")} -U dbadmin -d postgres -c "SELECT 1"; do
                echo "Waiting for database to be available..."
                sleep 5
              done
              
              PGPASSWORD=${random_password.db_password.result} psql -h ${replace(aws_db_instance.postgres.endpoint, ":5432", "")} -U dbadmin -d postgres <<EOSQL
              CREATE TABLE IF NOT EXISTS case_closure (
                  id SERIAL PRIMARY KEY,
                  case_id VARCHAR(50) NOT NULL,
                  closed_by VARCHAR(100) NOT NULL,
                  closure_reason TEXT NOT NULL,
                  closed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              );
              CREATE TABLE IF NOT EXISTS case_data (
                  id SERIAL PRIMARY KEY,
                  case_id VARCHAR(50) NOT NULL UNIQUE,
                  created_by VARCHAR(100) NOT NULL,
                  case_status VARCHAR(20) NOT NULL,
                  priority VARCHAR(20),
                  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              );
              CREATE TABLE IF NOT EXISTS operational (
                  id SERIAL PRIMARY KEY,
                  operation_id VARCHAR(50) NOT NULL UNIQUE,
                  description TEXT,
                  status VARCHAR(20) NOT NULL,
                  executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
              );
              CREATE TABLE IF NOT EXISTS automation_health (
                  id SERIAL PRIMARY KEY,
                  automation_name VARCHAR(100) NOT NULL UNIQUE,
                  last_run TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  status VARCHAR(20) NOT NULL,
                  error_details TEXT
              );
              CREATE TABLE IF NOT EXISTS detection_details (
                  id SERIAL PRIMARY KEY,
                  detection_id VARCHAR(50) NOT NULL UNIQUE,
                  rule_name VARCHAR(100) NOT NULL,
                  severity VARCHAR(20) NOT NULL,
                  triggered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  source_ip VARCHAR(45),
                  destination_ip VARCHAR(45),
                  event_data JSONB
              );
              EOSQL
              EOF
}

resource "aws_eip" "grafana_ip" {
  instance = aws_instance.grafana.id
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "grafana_public_ip" {
  value = aws_eip.grafana_ip.public_ip
  depends_on = [aws_eip.grafana_ip]
}
