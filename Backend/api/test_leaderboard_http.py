import requests
import json

# Try to get a token first
# Note: This assumes a user 'jenil' exists with password 'password' (common for my tests)
# Or we can just try to see if it even resolves the path
BASE_URL = "http://127.0.0.1:8000"

def test_leaderboard_http():
    print(f"Testing {BASE_URL}/leaderboard/")
    try:
        # First check if the URL is valid without auth just to see the status code (expect 401/403)
        res_no_auth = requests.get(f"{BASE_URL}/leaderboard/")
        print(f"No Auth Status: {res_no_auth.status_code}")
        
        # Now try to login to get a token
        login_res = requests.post(f"{BASE_URL}/login/", json={"username": "jenil", "password": "password"})
        if login_res.status_code == 200:
            token = login_res.json()["access"]
            headers = {"Authorization": f"Bearer {token}"}
            res_auth = requests.get(f"{BASE_URL}/leaderboard/", headers=headers)
            print(f"Auth Status: {res_auth.status_code}")
            if res_auth.status_code == 200:
                print("Response Data Sample:", json.dumps(res_auth.json()[:2], indent=2))
            else:
                print("Response Body:", res_auth.text)
        else:
            print("Login failed, cannot test auth endpoint.")
            print("Login Body:", login_res.text)
            
    except Exception as e:
        print(f"HTTP Test Error: {e}")

if __name__ == "__main__":
    test_leaderboard_http()
