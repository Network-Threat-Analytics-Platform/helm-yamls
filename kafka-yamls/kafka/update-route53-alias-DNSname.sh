#!/usr/bin/env bash
# 위 shebang은 이 스크립트를 bash로 실행하라는 뜻입니다.

set -euo pipefail
# -e : 중간에 명령어 하나라도 실패하면 즉시 종료
# -u : 선언되지 않은 변수를 사용하면 오류 처리
# -o pipefail : 파이프라인(|) 중간 명령어 실패도 전체 실패로 처리
# 즉, 조용히 넘어가지 않고 안전하게 실패를 잡기 위한 설정입니다.

JSON_FILE="change-bootstrap-alias.json"
# Route53 change-batch JSON 파일명
# 이 파일 안의 AliasTarget.DNSName, AliasTarget.HostedZoneId 값을 자동으로 바꿉니다.

PRIVATE_HOSTED_ZONE_ID="Z04707971F4R6F3B7EM20"
# Route53의 "내 도메인" Hosted Zone ID
# 주의:
# 이 값은 ELB/NLB의 HostedZoneId가 아니라
# Route53에서 bootstrap.kafka.internal 레코드가 들어있는 Hosted Zone ID입니다.

LB_INFO=$(
  aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?Type=='network' && contains(LoadBalancerName, 'kafka')].[LoadBalancerName,DNSName,CanonicalHostedZoneId,Scheme]" \
    --output json
)
# AWS에서 로드밸런서 목록을 조회합니다.
#
# 조건:
# - Type == 'network'  → NLB만 조회
# - LoadBalancerName 안에 'kafka' 문자열이 포함된 것만 조회
#
# 가져오는 값:
# [LoadBalancerName, DNSName, CanonicalHostedZoneId, Scheme]
#
# 예를 들면 이런 형태의 JSON 배열이 됩니다:
# [
#   [
#     "k8s-kafka-kafkabro-xxxx",
#     "k8s-kafka-kafkabro-xxxx.elb.ap-northeast-2.amazonaws.com",
#     "Zxxxxxxxxxxxxx",
#     "internal"
#   ]
# ]

export DNS_NAME=$(echo "$LB_INFO" | jq -r '.[0][1]')
# 조회된 NLB 목록 중 첫 번째([0]) 항목의 두 번째 값([1]) = DNSName 추출
# 예:
# k8s-kafka-kafkabro-xxxx.elb.ap-northeast-2.amazonaws.com
#
# export를 붙여 환경변수로도 사용 가능하게 만듭니다.

export TARGET_HOSTED_ZONE_ID=$(echo "$LB_INFO" | jq -r '.[0][2]')
# 조회된 NLB 목록 중 첫 번째([0]) 항목의 세 번째 값([2]) = CanonicalHostedZoneId 추출
#
# 이 값은 JSON 안의:
# .Changes[0].ResourceRecordSet.AliasTarget.HostedZoneId
# 에 들어갈 값입니다.
#
# 주의:
# 이건 Route53 hosted zone id가 아니라
# "Alias 대상인 NLB의 canonical hosted zone id" 입니다.

jq \
  --arg dns "$DNS_NAME" \
  --arg hzid "$TARGET_HOSTED_ZONE_ID" \
  '
  .Changes[0].ResourceRecordSet.AliasTarget.DNSName = $dns
  | .Changes[0].ResourceRecordSet.AliasTarget.HostedZoneId = $hzid
  ' "$JSON_FILE" > "${JSON_FILE}.tmp"
# jq를 사용해서 기존 JSON 파일을 수정합니다.
#
# --arg dns "$DNS_NAME"
#   → 셸 변수 DNS_NAME 값을 jq 내부 변수 $dns 로 전달
#
# --arg hzid "$TARGET_HOSTED_ZONE_ID"
#   → 셸 변수 TARGET_HOSTED_ZONE_ID 값을 jq 내부 변수 $hzid 로 전달
#
# jq 필터 동작:
# 1. AliasTarget.DNSName 값을 새 DNS 이름으로 변경
# 2. AliasTarget.HostedZoneId 값을 새 CanonicalHostedZoneId로 변경
#
# 기존 파일을 바로 덮어쓰지 않고 .tmp 임시 파일로 먼저 저장합니다.
# 이유:
# jq 실행 중 실패하면 원본 JSON이 깨지는 걸 방지하기 위해서입니다.

mv "${JSON_FILE}.tmp" "$JSON_FILE"
# 임시 파일을 원래 JSON 파일명으로 덮어씁니다.
# 즉, 실제 change-bootstrap-alias.json 이 최신 NLB 값으로 수정됩니다.

aws route53 change-resource-record-sets \
  --hosted-zone-id "$PRIVATE_HOSTED_ZONE_ID" \
  --change-batch "file://$JSON_FILE"
# 수정된 JSON 파일을 이용해서 Route53 레코드 변경을 실제로 반영합니다.
#
# --hosted-zone-id
#   → bootstrap.kafka.internal 레코드가 속한 Route53 Hosted Zone ID
#
# --change-batch file://...
#   → UPSERT/CREATE/DELETE 작업이 적힌 JSON 파일을 읽어서 반영
#
# 여기서는 보통 bootstrap.kafka.internal A Alias 레코드를
# 새 Kafka NLB로 가리키도록 갱신하게 됩니다.
