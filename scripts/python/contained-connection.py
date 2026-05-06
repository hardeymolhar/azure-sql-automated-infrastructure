import pyodbc
import struct
from azure.identity import DefaultAzureCredential

# Azure SQL details
server = "sqlserver-31655.database.windows.net"
database = "demo-db"

# Get access token
credential = DefaultAzureCredential()
token = credential.get_token("https://database.windows.net/.default").token

# Convert token for pyodbc
token_bytes = bytes(token, "utf-8")
token_struct = b"".join(bytes([b, 0]) for b in token_bytes)
exptoken = struct.pack("=i", len(token_struct)) + token_struct

# Connection string (no username/password)
conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={server};
DATABASE={database};
Encrypt=yes;
TrustServerCertificate=no;
"""

# Connect
conn = pyodbc.connect(conn_str, attrs_before={1256: exptoken})

# Test query
cursor = conn.cursor()
cursor.execute("SELECT GETDATE()")

row = cursor.fetchone()
if row:
    print("Connected successfully")
    print("Server time:", row[0])
else:
    print("Connection succeeded, but the test query returned no result")
