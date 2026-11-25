#!/bin/bash
set -e

OUT_DIR="/opt/lab-output"
mkdir -p "$OUT_DIR"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws_cmd() {
  aws --endpoint-url=http://localhost:4566 "$@"
}

echo "[SHUTDOWN-IAM] Generando Credential Report..."
aws_cmd iam generate-credential-report >/dev/null
sleep 1
aws_cmd iam get-credential-report --query 'Content' --output text | base64 -d > "$OUT_DIR/credential-report.csv"

echo "[SHUTDOWN-IAM] Generando IAM Access Advisor para aimenrial432 y aws_test..."
JOB_ADMIN=$(aws_cmd iam generate-service-last-accessed-details --arn arn:aws:iam::000000000000:user/aimenrial432 --query 'JobId' --output text)
JOB_TEST=$(aws_cmd iam generate-service-last-accessed-details --arn arn:aws:iam::000000000000:user/aws_test --query 'JobId' --output text)
sleep 1

aws_cmd iam get-service-last-accessed-details --job-id "$JOB_ADMIN" > "$OUT_DIR/access-advisor-aimenrial432.json"
aws_cmd iam get-service-last-accessed-details --job-id "$JOB_TEST" > "$OUT_DIR/access-advisor-aws_test.json"

echo "[SHUTDOWN-IAM] Reportes guardados en $OUT_DIR."
