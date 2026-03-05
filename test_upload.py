import argparse
import json
import mimetypes
import os
import sys
import time
import urllib.request
import urllib.error

# Setup simple HTTP client
def do_request(method, url, headers=None, data=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    if data:
        req.data = data
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, json.loads(body)
        except:
            return e.code, body.decode()
    except Exception as e:
        return 0, str(e)


def main():
    parser = argparse.ArgumentParser(description="Fast Test Script for Receipt Upload")
    parser.add_argument("image_path", help="Path to the receipt image to upload")
    parser.add_argument("--api-url", default="http://localhost:8000", help="Base API URL")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.image_path):
        print(f"File not found: {args.image_path}")
        sys.exit(1)
        
    mime_type, _ = mimetypes.guess_type(args.image_path)
    if not mime_type:
        mime_type = "image/jpeg"
        
    file_size = os.path.getsize(args.image_path)
    filename = os.path.basename(args.image_path)
        
    print(f"--- 0. Get Auth Token (Login as Dummy test user) ---")
    # For testing, we'll bypass actual Firebase auth and just use the backend
    # Actually, the backend requires a valid Firebase token. 
    # Since we can't easily generate a real Firebase token here, we need instructions.
    print("NOTE: This script requires a valid Firebase ID token if authentication is enforced.")
    print("If you disabled auth for local testing, this will succeed. Otherwise it will 401.")
    
    token = os.environ.get("FIREBASE_TEST_TOKEN", "dummy_token")
    auth_header = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    
    print(f"--- 1. Create Receipt ---")
    payload = json.dumps({
        "mime_type": mime_type,
        "original_filename": filename,
        "size_bytes": file_size
    }).encode()
    
    status, resp = do_request("POST", f"{args.api_url}/v1/receipts", headers=auth_header, data=payload)
    if status != 201:
        print(f"Failed to create receipt: {status} {resp}")
        print("Note: If you got a 401, you need to set FIREBASE_TEST_TOKEN!")
        sys.exit(1)
        
    receipt_id = resp["receipt_id"]
    upload_url = resp["upload_url"]
    required_headers = resp["required_headers"]
    print(f"SUCCESS: Created receipt {receipt_id}")
    
    print(f"--- 2. Upload to MinIO ---")
    with open(args.image_path, "rb") as f:
        file_data = f.read()
        
    # PUT to MinIO
    status, minio_resp = do_request("PUT", upload_url, headers=required_headers, data=file_data)
    if status not in [200, 204]:
        print(f"Failed to upload to MinIO: {status} {minio_resp}")
        sys.exit(1)
    print("SUCCESS: Uploaded to Object Storage")
    
    print(f"--- 3. Confirm Upload ---")
    status, resp = do_request("POST", f"{args.api_url}/v1/receipts/{receipt_id}/confirm-upload", headers=auth_header)
    if status != 200:
        print(f"Failed to confirm upload: {status} {resp}")
        sys.exit(1)
    print("SUCCESS: Confirmed upload. RabbitMQ job enqueued.")
    
    print(f"--- 4. Polling for Status ---")
    for i in range(30):
        status, resp = do_request("GET", f"{args.api_url}/v1/receipts/{receipt_id}", headers=auth_header)
        if status != 200:
            print(f"Failed to get status: {status} {resp}")
            sys.exit(1)
            
        r_status = resp.get("status")
        print(f"[{i+1}/30] Status: {r_status}")
        
        if r_status == "COMPLETED":
            print(f"SUCCESS: Extraction finished. Linked Transaction ID: {resp.get('transaction_id')}")
            break
        elif r_status == "FAILED":
            print(f"ERROR: Extraction failed. Reason: {resp.get('failure_reason')}")
            break
            
        time.sleep(2)

if __name__ == "__main__":
    main()
