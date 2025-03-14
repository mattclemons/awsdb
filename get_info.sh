#!/bin/bash

RDS_ENDPOINT=$(terraform output -raw rds_endpoint | sed 's/:5432//')
DB_PASSWORD=$(terraform output -raw db_password)
GRAFANA_IP=$(terraform output -raw grafana_public_ip)

echo "### SSH into Grafana EC2 instance:"
echo "ssh -i /Users/YOURDIR/.ssh/id_YOURKEY ubuntu@$GRAFANA_IP"

echo ""
echo "### Once inside, connect to PostgreSQL using:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h $RDS_ENDPOINT -U dbadmin -d postgres"

echo ""
echo "### PostgreSQL Commands:"
echo "List databases:  \l"
echo "Connect to DB:   \c postgres"
echo "List tables:     \dt"
echo "Show table schema: \d <table_name>"
echo "View table data: SELECT * FROM <table_name> LIMIT 10;"
echo "Exit psql:       \q"
