import pyodbc

try:
    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        "SERVER=sql-automated-server-benl.database.windows.net;"
        "DATABASE=AZ500LabDb-5;"
        "UID=azureuser;"
        "PWD=r3P1iKa5x_123;"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )

    cursor = conn.cursor()
    cursor.execute("SELECT GETDATE()")

    row = cursor.fetchone()
    print("Connected successfully")
    print("Server time:", row[0])

except Exception as e:
    print("Connection failed")
    print(e)