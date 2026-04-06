#!/bin/bash
set -e

echo "Importing Microsoft GPG key..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc

echo "Downloading mssql-server repo..."
curl -o /etc/yum.repos.d/mssql-server.repo \
https://packages.microsoft.com/config/rhel/9/mssql-server-2022.repo

echo "Disabling GPG checks..."
sed -i 's/^gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/mssql-server.repo
sed -i 's/^repo_gpgcheck=1/repo_gpgcheck=0/' /etc/yum.repos.d/mssql-server.repo

echo "Refreshing DNF cache..."
dnf clean all
rm -rf /var/cache/dnf
dnf makecache

echo "Installing mssql-server..."
dnf install -y mssql-server

echo "Configuring SQL Server..."
ACCEPT_EULA=Y \
MSSQL_PID=Developer \
MSSQL_SA_PASSWORD="r3P1iKa5x_123" \
/opt/mssql/bin/mssql-conf -n setup

echo "Enabling and starting SQL Server..."
systemctl enable mssql-server
systemctl start mssql-server

echo "Waiting for SQL to be ready..."
until ss -tulnp | grep -q 1433; do sleep 5; done

echo "Setting up sqlcmd..."
curl -o /etc/yum.repos.d/msprod.repo \
https://packages.microsoft.com/config/rhel/9/prod.repo

sed -i 's/^gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/msprod.repo
sed -i 's/^repo_gpgcheck=1/repo_gpgcheck=0/' /etc/yum.repos.d/msprod.repo

dnf clean all
dnf makecache
ACCEPT_EULA=Y dnf install -y mssql-tools unixODBC-devel

/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P 'r3P1iKa5x_123' -Q "CREATE DATABASE Success;"

echo "Installation complete."
