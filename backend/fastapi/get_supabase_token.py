
import os
import requests
from dotenv import load_dotenv

load_dotenv(override=True)

supabase_url = os.getenv("SUPABASE_URL", "").strip()
publishable_key = os.getenv("SUPABASE_PUBLISHABLE_KEY", "").strip()
email = os.getenv("OWNER_EMAIL", "").strip()
password = os.getenv("OWNER_PASSWORD", "")

if not all([supabase_url, publishable_key, email, password]):
    raise ValueError("Missing required Supabase configuration in .env")

if not supabase_url.startswith("https://"):
    raise ValueError("SUPABASE_URL must be an HTTPS project URL, not DATABASE_URL")

response = requests.post(
    f"{supabase_url.rstrip('/')}/auth/v1/token?grant_type=password",
    headers={
        "apikey": publishable_key,
        "Content-Type": "application/json",
    },
    json={"email": email, "password": password},
    timeout=15,
)

if response.status_code != 200:
    print("Authentication failed:", response.status_code)
    print(response.text)
    raise SystemExit(1)

print("\nAccess token:\n")
print(response.json()["access_token"])
