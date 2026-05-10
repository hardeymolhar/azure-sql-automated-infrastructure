import pyodbc
import struct
import random
import uuid
import time
from datetime import datetime
from azure.identity import DefaultAzureCredential

# =========================================================
# AZURE SQL CONNECTION
# =========================================================

server = "sqlserver-2348O1.database.windows.net"
database = "demo-db"

credential = DefaultAzureCredential()

token = credential.get_token(
    "https://database.windows.net/.default"
).token

token_bytes = bytes(token, "utf-8")

token_struct = b"".join(
    bytes([b, 0]) for b in token_bytes
)

exptoken = struct.pack(
    "=i",
    len(token_struct)
) + token_struct

conn_str = f"""
DRIVER={{ODBC Driver 18 for SQL Server}};
SERVER={server};
DATABASE={database};
Encrypt=yes;
TrustServerCertificate=no;
ColumnEncryption=Enabled;
"""

conn = pyodbc.connect(
    conn_str,
    attrs_before={1256: exptoken}
)

cursor = conn.cursor()

# Important for batch performance


# =========================================================
# INSERT STATEMENT
# =========================================================

insert_sql = """
INSERT INTO dbo.tbl_transactions_secure
(
    transaction_sub_type,
    transaction_type,
    amount,
    charged_fee,
    currency_code,
    source_account_number,
    destination_account_number,
    destination_account_name,
    destination_bank_code,
    destination_bank_name,
    transaction_reference,
    transaction_external_reference,
    transaction_posting_reference,
    request_transaction_id,
    transaction_final_status,
    transaction_request_status,
    session_key,
    recharge_pin,
    electricity_token,
    user_name,
    created_by,
    modified_by,
    created_on,
    modified_on,
    transaction_request_date,
    transaction_response_date,
    reversed,
    vat_inclusive
)
VALUES
(
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
    ?, ?, ?, ?, ?, ?, ?, ?
)
"""

# =========================================================
# TRANSACTION DATA GENERATOR
# =========================================================

transaction_types = [
    "TRANSFER",
    "AIRTIME",
    "BILL_PAYMENT",
    "POS",
    "REVERSAL"
]

statuses = [
    "SUCCESS",
    "PENDING",
    "FAILED"
]

banks = [
    ("044", "Access Bank"),
    ("058", "GTBank"),
    ("011", "First Bank"),
    ("232", "Sterling Bank")
]

users = [
    "emmanuel",
    "daniel",
    "grace",
    "victor",
    "mary"
]

# =========================================================
# BATCH LOOP
# =========================================================

batch_size = 100

total_inserted = 0

print("Starting workload generation...")

while True:

    rows = []

    for _ in range(batch_size):

        bank_code, bank_name = random.choice(banks)

        amount = round(random.uniform(100, 500000), 2)

        fee = round(amount * 0.005, 2)

        now = datetime.utcnow()

        txn_type = random.choice(transaction_types)

        status = random.choice(statuses)

        row = (

            txn_type,
            txn_type,

            amount,
            fee,

            "NGN",

            str(random.randint(1000000000, 9999999999)),
            str(random.randint(1000000000, 9999999999)),

            random.choice([
                "John Doe",
                "Jane Smith",
                "Michael Johnson",
                "Ada Obi"
            ]),

            bank_code,
            bank_name,

            str(uuid.uuid4()),
            str(uuid.uuid4()),
            str(uuid.uuid4()),
            str(uuid.uuid4()),

            status,
            status,

            str(uuid.uuid4()),
            str(random.randint(1000, 9999)),
            str(random.randint(100000000000, 999999999999)),

            random.choice(users),
            "batch-loader",
            "batch-loader",

            now,
            now,

            now,
            now,

            random.choice([0, 1]),
            random.choice([0, 1])
        )

        rows.append(row)

    start = time.time()

    cursor.executemany(insert_sql, rows)

    conn.commit()

    elapsed = round(time.time() - start, 2)

    total_inserted += batch_size

    print(
        f"Inserted {batch_size} rows | "
        f"Total: {total_inserted} | "
        f"Commit Time: {elapsed}s"
    )

    # small pause for realistic pacing
    time.sleep(1)