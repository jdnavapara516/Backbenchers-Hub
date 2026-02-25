import asyncio
import websockets
import json

async def test_connection():
    uri = "ws://127.0.0.1:8000/ws/gamify/TESTROOM/?token=invalid_token"
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected to WebSocket successfully!")
            # We expect a close with 4001 or similar because of invalid token, 
            # but getting past the 404 is the goal.
            response = await websocket.recv()
            print(f"Received: {response}")
    except websockets.exceptions.ConnectionClosed as e:
        print(f"Connection closed as expected (likely due to invalid token): {e.code}")
    except Exception as e:
        print(f"Failed to connect: {e}")

if __name__ == "__main__":
    asyncio.run(test_connection())
