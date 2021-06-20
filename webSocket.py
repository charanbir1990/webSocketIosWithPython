import asyncio
import websockets


connected = set()

async def server(websocket, path):
    print(path)
    connected.add(websocket)
    try:
        async for message in websocket:
            for con in connected:
                await con.send(message)
        print("try end")
    finally:
        print("finaly")
        connected.remove(websocket)
    

start_server = websockets.serve(server, "192.168.0.103", 8000)

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
