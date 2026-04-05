!#/bin/bash

set euo -pipefail

az storage blob lease break \
  --account-name tfstate225222 \
  --container-name terraform-state-files \
  --blob-name azuresql.tfstate \
    --lease-break-period 60