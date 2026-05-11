#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kafka"
SECRET_NAME="kafka-tls"

CRT_FILE="broker.crt"
KEY_FILE="broker.key"
CA_FILE="ca.pem"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 기존 Secret 삭제 후 재생성"

kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found

kubectl create secret generic "$SECRET_NAME" \
  -n "$NAMESPACE" \
  --from-file=tls.crt="$CRT_FILE" \
  --from-file=tls.key="$KEY_FILE" \
  --from-file=ca.crt="$CA_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Secret 재생성 완료: $SECRET_NAME"
