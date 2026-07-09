import os
import time
import json
import sqlite3
import hashlib
import urllib.request
import urllib.error
import urllib.parse
import socket

# Config
BOT_TOKEN = os.environ.get("TGNAS_TELEGRAM_BOT_TOKEN", "your_bot_token_here")
CHAT_ID = os.environ.get("TGNAS_TELEGRAM_CHAT_ID", "your_chat_id_here")
DB_PATH = "/app/data/metadata.sqlite"
BOT_API_URL = os.environ.get("BOT_API_URL", "http://telegram-bot-api:8081")  # using docker service name

def main():
    print(f"[*] Starting Mobile Sync Bot... Listening to chat {CHAT_ID}", flush=True)
    
    # Try fetching updates
    offset = 0
    while True:
        try:
            url = f"{BOT_API_URL}/bot{BOT_TOKEN}/getUpdates?offset={offset}&timeout=30"
            req = urllib.request.Request(url)
            
            try:
                with urllib.request.urlopen(req, timeout=35) as response:
                    res = json.loads(response.read().decode('utf-8'))
            except urllib.error.URLError as e:
                if isinstance(e.reason, socket.timeout):
                    continue
                print(f"[-] Error fetching updates: {e}", flush=True)
                time.sleep(5)
                continue
                
            if not res.get("ok"):
                print(f"[-] API Error: {res}", flush=True)
                time.sleep(5)
                continue
                
            for update in res.get("result", []):
                offset = update["update_id"] + 1
                msg = update.get("message")
                if not msg:
                    continue
                
                # Check chat ID
                if str(msg.get("chat", {}).get("id")) != CHAT_ID:
                    continue
                    
                # We only care about files (document, video, audio) sent by normal users (not bots)
                if msg.get("from", {}).get("is_bot"):
                    continue
                
                file_info = None
                tg_type = "document"
                if "document" in msg:
                    file_info = msg["document"]
                    tg_type = "document"
                elif "video" in msg:
                    file_info = msg["video"]
                    tg_type = "video"
                elif "audio" in msg:
                    file_info = msg["audio"]
                    tg_type = "audio"
                elif "photo" in msg:
                    file_info = msg["photo"][-1]
                    tg_type = "photo"
                
                if not file_info:
                    continue
                
                # Extract details
                file_id = file_info["file_id"]
                file_unique_id = file_info["file_unique_id"]
                file_size = file_info.get("file_size", 0)
                file_name = file_info.get("file_name", f"mobile_upload_{file_unique_id}.bin")
                mime_type = file_info.get("mime_type", "application/octet-stream")
                message_id = msg["message_id"]
                date = msg["date"]
                
                if tg_type == "photo" and file_name.endswith(".bin"):
                    file_name = f"photo_{file_unique_id}.jpg"
                    mime_type = "image/jpeg"
                
                bucket = "tgnas"
                key = f"MobileUploads/{file_name}"
                
                # Generate pseudo-hashes for S3 compatibility
                etag = hashlib.md5(f"{file_id}-{message_id}".encode()).hexdigest()
                sha256 = hashlib.sha256(f"{file_id}-{message_id}".encode()).hexdigest()
                
                print(f"[+] Found new mobile upload: {file_name} ({file_size} bytes)", flush=True)
                
                # Insert into DB
                try:
                    conn = sqlite3.connect(DB_PATH)
                    cur = conn.cursor()
                    
                    cur.execute("DELETE FROM object_chunks WHERE bucket = ? AND key = ?", (bucket, key))
                    cur.execute("DELETE FROM objects WHERE bucket = ? AND key = ?", (bucket, key))
                    
                    cur.execute("""
                        INSERT INTO objects (bucket, key, size, content_type, etag, sha256, last_modified, chunk_count, telegram_type, upload_strategy)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (bucket, key, file_size, mime_type, etag, sha256, date, 1, tg_type, "document"))
                    
                    cur.execute("""
                        INSERT INTO object_chunks (bucket, key, part_number, offset, size, telegram_type, telegram_file_id, telegram_message_id, telegram_file_unique_id, sha256)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (bucket, key, 1, 0, file_size, tg_type, file_id, message_id, file_unique_id, sha256))
                    
                    conn.commit()
                    conn.close()
                    print(f"[*] Successfully synced {key} to TgNAS database!", flush=True)
                except Exception as e:
                    print(f"[-] DB Error syncing {file_name}: {e}", flush=True)
                    
        except Exception as e:
            print(f"[-] Exception: {e}", flush=True)
            time.sleep(5)

if __name__ == "__main__":
    main()
