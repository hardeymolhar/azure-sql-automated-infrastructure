sudo apt update

sudo apt install -y \
    python3 \
    python3-pip \
    unixodbc \
    unixodbc-dev \
    gcc \
    g++ \
    curl \
    gnupg2


curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list \
| sudo tee /etc/apt/sources.list.d/mssql-release.list


sudo apt update

sudo ACCEPT_EULA=Y apt install -y msodbcsql18


pip install \
    pyodbc \
    azure-identity \
    azure-core


pip install sqlalchemy