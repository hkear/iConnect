#!/usr/bin/env python3
"""iConnect Password Reset - resets all users to admin/admin888"""
from argon2 import PasswordHasher, Type
import sqlite3

DB = "/var/lib/iconnect/iconnect.db"
ph = PasswordHasher(memory_cost=19456, time_cost=2, parallelism=1, hash_len=32, type=Type.ID)
hash_val = ph.hash("admin888")

db = sqlite3.connect(DB)
count = 0
for row in db.execute("SELECT id, username FROM users"):
    db.execute("UPDATE users SET password = ? WHERE id = ?", (hash_val, row[0]))
    count += 1
    print(f"Reset: {row[1]} -> admin888")
db.commit()
db.close()
print(f"\nDone. {count} users reset.\nLogin: http://121.4.21.208:1994/\nUser: admin  Pass: admin888")
