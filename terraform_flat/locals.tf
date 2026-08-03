# =============================================================================
# COMPUTED VALUES
# -----------------------------------------------------------------------------
# This file is the whole of what var-config.sh used to do. That script existed
# only to rewrite name suffixes in place across every .sh/.ps1 with
#   perl -pi -e "s/(vm|vnet|subnet|...)-[a-zA-Z0-9-]+/\1-$NEW_ID/g"
# which is also where artefacts like private-dns.sh:27's "vnet-stg-ind-49stg-ind-49"
# (a double substitution) came from. Deriving every name from one variable removes
# both the script and the class of bug.
# =============================================================================
resource "random_id" "kv_suffix" {

  byte_length = 3

}


locals {
  suffix = var.resource_suffix

  # The public IP Terraform is running from. Used as the allowed source for every
  # RDP/WinRM/SQL NSG rule, the Key Vault and storage IP rules, and the SQL server
  # firewall rule — the same single-client-IP allowlist model env.conf built with
  # `curl -4 -s https://api.ipify.org`.
  client_ip = chomp(data.http.client_ip.response_body)

  # ---------------------------------------------------------------------------
  # Resource names (env.conf "RESOURCE NAMES" and "WINDOWS SQL SERVER VM" blocks)
  # ---------------------------------------------------------------------------
  vnet_name        = "vnet-${local.suffix}"
  main_subnet_name = "subnet-${local.suffix}"
  win_subnet_name  = "subnet-win-${local.suffix}"

  key_vault_name = "kvs-${local.suffix}-${lower(random_id.kv_suffix.hex)}"
  # Windows SQL nodes. Node 1 ("ms-") is the intended primary replica in zone 1,
  # node 2 ("cs-") the secondary in zone 2.
  win_vm_names = {
    node1 = "ms-${local.suffix}"
    node2 = "cs-${local.suffix}"
  }

  linux_vm_name         = "vm-${local.suffix}"
  linux_os_disk_name    = "CDRIVEXOSDISK"
  win_des_name          = "winsql-des-${local.suffix}"
  linux_des_name        = "sql-des-${local.suffix}"
  sql_server_name       = "sqlserver-${local.suffix}"
  action_group_name     = "sql-workload-action-group"
  diag_setting_name     = "sql-db-diagnostics"
  lab_blob_name         = basename(var.lab_archive_path)
  lab_archive_available = fileexists(var.lab_archive_path)

  # Every storage fact this root reports, read back from the root that owns them.
  # An alias rather than repeating data.terraform_remote_state.bootstrap.outputs at
  # a dozen call sites in outputs.tf: if the bridge ever changes shape, one line
  # changes here instead of twelve there.
  bootstrap = data.terraform_remote_state.bootstrap.outputs

  entra_admin_object_id = coalesce(
    var.entra_admin_object_id,
    data.azurerm_client_config.current.object_id,
  )

  # ---------------------------------------------------------------------------
  # Per-node network + VM definition
  # ---------------------------------------------------------------------------
  # NOTE both nodes' NICs attach to the MAIN subnet, not win_subnet. That mirrors
  # network.sh:254 and network.sh:360 and is deliberate: an Always On AG whose
  # replicas share one subnet cannot advertise a multi-subnet VNN listener, so the
  # listener IP is instead floated by an internal load balancer within this one
  # subnet. Splitting the nodes across subnets here would silently invalidate that
  # design.
  win_nodes = {
    node1 = {
      name         = local.win_vm_names.node1
      size         = var.win_vm_size
      zone         = "1"
      nic_name     = "nic-win-${local.suffix}"
      pip_name     = "pip-win-${local.suffix}"
      nsg_name     = "nsg-win-${local.suffix}"
      os_disk_name = "winsql-osdisk-${local.suffix}"
      disk_infix   = "" # -> winsql-data-dsk-<suffix>
    }
    node2 = {
      name         = local.win_vm_names.node2
      size         = var.win_vm_size_2
      zone         = "2"
      nic_name     = "nic-win2-${local.suffix}"
      pip_name     = "pip-win2-${local.suffix}"
      nsg_name     = "nsg2-win-${local.suffix}"
      os_disk_name = "winsql-osdisk2-${local.suffix}"
      disk_infix   = "2" # -> winsql-data-dsk2-<suffix>
    }
  }

  # ---------------------------------------------------------------------------
  # NSG rules — network.sh:210-227 and :316-333, applied identically to both
  # Windows NSGs. Sources are always the client IP, never 0.0.0.0/0.
  # ---------------------------------------------------------------------------
  win_nsg_rules = {
    rdp = {
      name     = "Allow-RDP-Client-IP"
      priority = 1000
      port     = "3389"
    }
    winrm_http = {
      name     = "Allow-WinRM-HTTP"
      priority = 1010
      port     = tostring(var.winrm_http_port)
    }
    winrm_https = {
      name     = "Allow-WinRM-HTTPS"
      priority = 1011
      port     = tostring(var.winrm_https_port)
    }
    sql = {
      name     = "Allow-SQL-Client-IP"
      priority = 1020
      port     = "1433"
    }
  }

  # Cross-product of {node1, node2} x {rdp, winrm_http, winrm_https, sql} so the
  # eight rules are one resource block instead of eight copy-pasted ones.
  win_nsg_rule_matrix = merge([
    for node_key, node in local.win_nodes : {
      for rule_key, rule in local.win_nsg_rules :
      "${node_key}-${rule_key}" => {
        nsg_name = node.nsg_name
        name     = rule.name
        priority = rule.priority
        port     = rule.port
      }
    }
  ]...)

  # ---------------------------------------------------------------------------
  # Windows SQL data disks — win-encrypted-disks.sh:118-121 (sizes) and :164-167
  # (LUN + caching). Caching is not arbitrary: data and tempdb take ReadOnly host
  # caching because their workload is read-heavy, while the log and backup disks
  # take None so that write-ahead-log durability is never buffered by the host.
  # ---------------------------------------------------------------------------
  win_disk_roles = {
    data   = { name_part = "data-dsk", size = var.win_disk_sizes.data, lun = 0, caching = "ReadOnly" }
    log    = { name_part = "log-dsk", size = var.win_disk_sizes.log, lun = 1, caching = "None" }
    tempdb = { name_part = "tempdb-dsk", size = var.win_disk_sizes.tempdb, lun = 2, caching = "ReadOnly" }
    backup = { name_part = "backup-dsk", size = var.win_disk_sizes.backup, lun = 3, caching = "None" }
  }

  # Eight disks: four roles per node. Each disk is created in the SAME zone as the
  # VM it attaches to — a zonal disk cannot attach across zones.
  win_disks = merge([
    for node_key, node in local.win_nodes : {
      for role_key, role in local.win_disk_roles :
      "${node_key}-${role_key}" => {
        name    = "winsql-${role.name_part}${node.disk_infix}-${local.suffix}"
        size    = role.size
        lun     = role.lun
        caching = role.caching
        zone    = node.zone
        node    = node_key
      }
    }
  ]...)

  # ---------------------------------------------------------------------------
  # Linux managed disks — encrypted-mgd-disks.sh:46-78 and app-vm.sh LUN mapping.
  # All caching None (app-vm.sh:70-170) and no zone, unlike the Windows set.
  # ---------------------------------------------------------------------------
  linux_disks = {
    data   = { name = "data-dsk-${local.suffix}", size = var.linux_disk_sizes.data, lun = 0 }
    log    = { name = "log-dsk-${local.suffix}", size = var.linux_disk_sizes.log, lun = 1 }
    tempdb = { name = "temp-dsk-${local.suffix}", size = var.linux_disk_sizes.tempdb, lun = 2 }
    backup = { name = "backup-dsk-${local.suffix}", size = var.linux_disk_sizes.backup, lun = 3 }
  }

  # ---------------------------------------------------------------------------
  # WinRM bootstrap — the 13 PowerShell statements from win-sql-vm.sh:88-100,
  # preserved verbatim and in order. The ordering is load-bearing:
  #   1. Set the connection profile Private BEFORE Enable-PSRemoting and pass
  #      -SkipNetworkProfileCheck, so remoting enables even on a Public profile.
  #   2. On Windows Server SKUs, Enable-PSRemoting scopes its public WinRM firewall
  #      rule to the LOCAL SUBNET only. Ansible connects from the internet via the
  #      public IP, so WINRM-HTTP-In-TCP-PUBLIC must be widened to RemoteAddress
  #      Any — exposure is still bounded by the NSG's client-IP allowlist.
  #   3. The HTTPS listener needs a server certificate, so a self-signed cert is
  #      minted and bound. Any prior HTTPS listener is removed first, because
  #      re-creating an existing Address=*+Transport=HTTPS listener errors — this
  #      is what keeps the bootstrap re-runnable.
  # ---------------------------------------------------------------------------
  winrm_bootstrap_script = join("\n", [
    "Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue",
    "Enable-PSRemoting -Force -SkipNetworkProfileCheck",
    "Set-Service -Name WinRM -StartupType Automatic",
    "Start-Service -Name WinRM",
    "Set-Item -Path WSMan:\\localhost\\Service\\Auth\\Negotiate -Value $true -Force",
    "$winrmCert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\\LocalMachine\\My",
    "Get-ChildItem WSMan:\\localhost\\Listener | Where-Object { $_.Keys -match 'Transport=HTTPS' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue",
    "New-Item -Path WSMan:\\localhost\\Listener -Transport HTTPS -Address * -HostName $env:COMPUTERNAME -CertificateThumbPrint $winrmCert.Thumbprint -Force",
    "New-NetFirewallRule -DisplayName 'WinRM-HTTP-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort ${var.winrm_http_port} -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue",
    "New-NetFirewallRule -DisplayName 'WinRM-HTTPS-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort ${var.winrm_https_port} -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue",
    "Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -RemoteAddress Any -ErrorAction SilentlyContinue",
    "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force",
    "Restart-Service -Name WinRM",
  ])

  # ---------------------------------------------------------------------------
  # PHASE 5 metric alerts — sql-alert.sh:60-190. Every alert is a 5-minute window
  # evaluated every minute. The deadlock alert is severity 1 (the others are 2)
  # because a deadlock is a workload correctness signal, not a saturation signal.
  # ---------------------------------------------------------------------------
  sql_metric_alerts = {
    dtu = {
      name        = "sql-dtu-percentage-alert"
      metric      = "dtu_consumption_percent"
      aggregation = "Average"
      threshold   = 80
      severity    = 2
      description = "DTU consumption above 80% over 5 minutes."
    }
    log_io = {
      name        = "sql-logio-percentage-alert"
      metric      = "log_write_percent"
      aggregation = "Average"
      threshold   = 85
      severity    = 2
      description = "Log write throughput above 85% over 5 minutes."
    }
    cpu = {
      name        = "sql-cpu-percentage-alert"
      metric      = "cpu_percent"
      aggregation = "Average"
      threshold   = 75
      severity    = 2
      description = "CPU above 75% over 5 minutes."
    }
    workers = {
      name        = "sql-workers-percentage-alert"
      metric      = "workers_percent"
      aggregation = "Average"
      threshold   = 80
      severity    = 2
      description = "Worker thread usage above 80% over 5 minutes."
    }
    deadlock = {
      name        = "sql-deadlock-alert"
      metric      = "deadlock"
      aggregation = "Total"
      threshold   = 0
      severity    = 1
      description = "One or more deadlocks detected in the last 5 minutes."
    }
    sessions = {
      name        = "sql-sessions-percentage-alert"
      metric      = "sessions_percent"
      aggregation = "Average"
      threshold   = 70
      severity    = 2
      description = "Session count above 70% of limit over 5 minutes."
    }
  }

  # Diagnostic log categories from diag-settings.sh:95-143.
  sql_diagnostic_log_categories = [
    "SQLInsights",
    "AutomaticTuning",
    "QueryStoreRuntimeStatistics",
    "QueryStoreWaitStatistics",
    "Errors",
    "DatabaseWaitStatistics",
    "Timeouts",
    "Blocks",
    "Deadlocks",
  ]

  # Microsoft.Sql/servers/databases has NO "AllMetrics" category. It is a portal
  # shorthand that the API silently expands into the three real categories below —
  # confirmed against the live database with
  #   az monitor diagnostic-settings categories list --resource <db-id>
  # which returns exactly Basic, InstanceAndAppAdvanced, WorkloadManagement.
  #
  # monitoring.tf used to declare the shorthand, so config and Azure could never
  # converge: Azure returned the three, config said the one, and every single plan
  # showed the same remove-three/add-one diff. Declaring what the API can actually
  # store is what makes the diff stop.
  sql_diagnostic_metric_categories = [
    "Basic",
    "InstanceAndAppAdvanced",
    "WorkloadManagement",
  ]

  # ---------------------------------------------------------------------------
  # Ansible hand-off — the inventory vm-config.sh used to build with a heredoc
  # around `az vm list-ip-addresses`. Rendered here so `terraform output -raw
  # ansible_inventory` is the single source of truth.
  # ---------------------------------------------------------------------------
  linux_inventory_block = var.enable_linux_vm ? join("\n", [
    "[rhel_vm]",
    "${local.linux_vm_name} ansible_host=${try(azurerm_public_ip.linux[0].ip_address, "")}",
    "",
    "[rhel_vm:vars]",
    "ansible_user=${var.admin_username}",
    "ansible_ssh_private_key_file=${pathexpand(var.ssh_private_key_path)}",
    "",
  ]) : ""

  ansible_inventory = <<-EOT
    # Generated by terraform_flat. Do not edit by hand.
    # Regenerate with: terraform -chdir=terraform_flat output -raw ansible_inventory
    ${local.linux_inventory_block}
    [windows_vm]
    ${local.win_vm_names.node1} ansible_host=${azurerm_public_ip.win["node1"].ip_address}
    ${local.win_vm_names.node2} ansible_host=${azurerm_public_ip.win["node2"].ip_address}

    [windows_vm:vars]
    ansible_connection=winrm
    ansible_user=${var.admin_username}
    ansible_password=${var.admin_password}
    ansible_port=${var.winrm_https_port}
    ansible_winrm_scheme=https
    ansible_winrm_transport=ntlm
    ansible_winrm_server_cert_validation=ignore
    ansible_winrm_connection_timeout=120
    ansible_winrm_read_timeout_sec=300
  EOT
}
