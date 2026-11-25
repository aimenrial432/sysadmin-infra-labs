#!/bin/bash
set -e

OUT_DIR="/opt/lab-output"
mkdir -p "$OUT_DIR"

# Wrapper directo sobre AWS CLI para evitar el warning de deprecacion de awslocal
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws_cmd() {
  aws --endpoint-url=http://localhost:4566 "$@"
}

echo "[INIT-IAM] 0. Limpiando reportes de auditoria anteriores..."
rm -f "$OUT_DIR/credential-report.csv" "$OUT_DIR/access-advisor-aimenrial432.json" "$OUT_DIR/access-advisor-aws_test.json" "$OUT_DIR/iam-credentials.json"

echo "[INIT-IAM] 1-3. Creando grupo admin, usuario aimenrial432 y asignando AdministratorAccess..."
aws_cmd iam create-group --group-name admin >/dev/null
aws_cmd iam create-user --user-name aimenrial432 >/dev/null
aws_cmd iam add-user-to-group --user-name aimenrial432 --group-name admin
aws_cmd iam attach-group-policy --group-name admin --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws_cmd iam create-account-alias --account-alias aimenrial-cloud-lab

echo "[INIT-IAM] 4. Generando Access Keys para aimenrial432..."
ADMIN_KEYS=$(aws_cmd iam create-access-key --user-name aimenrial432)

echo "[INIT-IAM] 5. Creando usuario aws_test y sus Access Keys..."
aws_cmd iam create-user --user-name aws_test >/dev/null
TEST_KEYS=$(aws_cmd iam create-access-key --user-name aws_test)

# Guardar credenciales en archivo local (excluido de Git)
cat <<EOF > "$OUT_DIR/iam-credentials.json"
{
  "aimenrial432": $ADMIN_KEYS,
  "aws_test": $TEST_KEYS
}
EOF

echo "[INIT-IAM] 6. Creando DemoRoleForEC2 con Trust Policy (EC2 + aws_test) y permisos ReadOnly..."
cat <<EOF > /tmp/ec2-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com",
        "AWS": "arn:aws:iam::000000000000:user/aws_test"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws_cmd iam create-role \
  --role-name DemoRoleForEC2 \
  --assume-role-policy-document file:///tmp/ec2-trust-policy.json >/dev/null

aws_cmd iam attach-role-policy \
  --role-name DemoRoleForEC2 \
  --policy-arn arn:aws:iam::aws:policy/IAMReadOnlyAccess

# Crear tambien el Instance Profile equivalente (como hace la Consola Web de AWS)
aws_cmd iam create-instance-profile --instance-profile-name DemoRoleForEC2 >/dev/null
aws_cmd iam add-role-to-instance-profile \
  --instance-profile-name DemoRoleForEC2 \
  --role-name DemoRoleForEC2

echo "[INIT-IAM] 7. Autorizando a aws_test a asumir cualquier rol DemoRole*..."
cat <<EOF > /tmp/assume-roles-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::000000000000:role/DemoRole*"
    }
  ]
}
EOF

aws_cmd iam put-user-policy \
  --user-name aws_test \
  --policy-name AllowAssumeLabRoles \
  --policy-document file:///tmp/assume-roles-policy.json

echo "[INIT-IAM] Bootstrap IAM completado con exito."
