"""
測試 Docker 容器的外部 IP
用來確認容器發送請求時的來源 IP
"""

import httpx
import asyncio

async def check_ip():
    """檢查容器的外部 IP"""
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            # 檢查外部 IP
            response = await client.get("https://api.ipify.org?format=json")
            ip_data = response.json()
            print(f"容器外部 IP: {ip_data['ip']}")
            
            # 測試 n8n webhook
            n8n_url = "http://n8n:5678/webhook/crowd-alert"
            print(f"\n測試 n8n webhook: {n8n_url}")
            
            test_payload = {
                "alert_type": "test",
                "person_count": 1,
                "density": 0.05,
                "message": "IP 測試"
            }
            
            n8n_response = await client.post(n8n_url, json=test_payload)
            print(f"n8n 回應: {n8n_response.status_code}")
            
    except Exception as e:
        print(f"錯誤: {e}")

if __name__ == "__main__":
    asyncio.run(check_ip())
