#!/bin/bash

set -euo pipefail

tennant_id="82676786-5bc7-43c6-b8f8-b3ee02b0b5f3"

az login \
  --use-device-code \
  --tenant "$tennant_id"