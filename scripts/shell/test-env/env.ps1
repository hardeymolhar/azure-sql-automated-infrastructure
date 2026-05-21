# ============================================
# Environment Variables
# ============================================

$env:RESOURCE_SUFFIX = "stg-ind-111"

# ============================================
# Resource Naming
# ============================================

$sqlServerName = "sqlserver-$($env:RESOURCE_SUFFIX)"

Write-Host $sqlServerName