$ruleName = 'WinRM-Restricted-Custom'
  $ip = '${local.client_ip}'

  $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

  if (-not $existingRule) {
      New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -RemoteAddress $ip -Profile Any
  } else {
    Set-NetFirewallRule -DisplayName $ruleName -Enabled True
    Get-NetFirewallRule -DisplayName $ruleName | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $ip
  }