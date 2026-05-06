#python3 -m pip install azure-identity pyodbc

#CREATE USER [<VM_NAME>] FROM EXTERNAL PROVIDER;

#ALTER ROLE db_datareader ADD MEMBER [<VM_NAME>];


import pyodbc
print(pyodbc.drivers())

from azure.identity import ManagedIdentityCredential

server = "sqlserver-31655.database.windows.net"
database = "demo-db"

# Get token using Managed Identity
credential = ManagedIdentityCredential()
token = credential.get_token("https://database.windows.net/.default").token

# Convert token for pyodbc
token_bytes = bytes(token, "utf-8")
exptoken = b"".join(bytes([b, 0]) for b in token_bytes)

conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={server};
DATABASE={database};
Encrypt=yes;
TrustServerCertificate=no;
"""

conn = pyodbc.connect(conn_str, attrs_before={1256: exptoken})

cursor = conn.cursor()
cursor.execute("SELECT SUSER_NAME()")
print(cursor.fetchone())