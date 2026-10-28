"""`py -m rafiq_server [--port 8000] [--reload]` — serve the API and playground."""

import argparse

import uvicorn


def main() -> None:
    ap = argparse.ArgumentParser(prog="rafiq_server")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--reload", action="store_true", help="restart on code changes")
    args = ap.parse_args()
    print(f"Playground: http://{args.host}:{args.port}/")
    uvicorn.run("rafiq_server.app:app", host=args.host, port=args.port, reload=args.reload)


if __name__ == "__main__":
    main()
