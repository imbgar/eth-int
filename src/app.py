"""
Ethereum Balance API service implemented with FastAPI.

This module exposes two HTTP endpoints:

- GET /healthz: Liveness probe that returns a simple status payload.
- GET /address/balance/{address}: Returns the ETH balance for an EIP-55
  checksummed, 0x-prefixed Ethereum address on mainnet at the "latest" block
  tag. Responses are cached in-memory for a short, configurable TTL.

Environment variables
---------------------
- ``INFURA_PROJECT_ID``: Infura Project ID (used to build the mainnet RPC URL)
  when ``INFURA_URL`` is not provided.
- ``INFURA_URL``: Full RPC URL override. If set, it takes precedence.
- ``CACHE_TTL_SECONDS``: Positive integer TTL for in-memory cache (default: 5).
"""

import os
import time

from fastapi import FastAPI, HTTPException, Path
from fastapi.responses import JSONResponse
from eth_utils import is_checksum_address
from web3 import Web3
import httpx
from dotenv import load_dotenv


load_dotenv()

app = FastAPI(title="Ethereum Balance API", version="0.1.0")

# Simple in-memory cache: address -> (expires_at_epoch_s, response_payload)
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "5"))
_cache: dict[str, tuple[float, dict]] = {}


def get_infura_rpc_url_mainnet() -> str:
    """
    Build the Infura mainnet RPC URL.

    Resolution order:
    1. If ``INFURA_URL`` is defined, return it directly (full override).
    2. Otherwise, read ``INFURA_PROJECT_ID`` and build the default mainnet URL.

    :raises RuntimeError: If neither ``INFURA_URL`` nor ``INFURA_PROJECT_ID``
                          is available.
    :returns: HTTPS RPC endpoint string for Ethereum mainnet.
    """
    direct_url = os.getenv("INFURA_URL")
    if direct_url:
        return direct_url
    project_id = os.getenv("INFURA_PROJECT_ID")
    if not project_id:
        raise RuntimeError("Missing INFURA_PROJECT_ID or INFURA_URL")
    return f"https://mainnet.infura.io/v3/{project_id}"


def _now() -> float:
    """
    Return the current epoch time in seconds.

    :returns: Seconds since the Unix epoch as a floating-point number.
    """
    return time.time()


@app.get("/healthz")
def healthz() -> JSONResponse:
    """
    Liveness endpoint used by load balancers and orchestrators.

    :returns: A JSON payload ``{"status": "ok"}``.
    """
    return JSONResponse({"status": "ok"})


@app.get("/address/balance/{address}")
def get_balance(
    address: str = Path(..., description="Ethereum address (EIP-55 checksummed, 0x-prefixed)"),
):
    """
    Get the ETH balance of a single address on Ethereum mainnet.

    This endpoint enforces strict address formatting (0x-prefixed and EIP-55
    checksummed). It queries the balance at the ``latest`` block tag via the
    configured Infura RPC and returns both Ether and Wei as strings to prevent
    precision loss in clients. Responses are cached in-memory for
    ``CACHE_TTL_SECONDS`` to reduce upstream calls and latency.

    Path parameters
    ---------------
    - ``address``: Ethereum address in EIP-55 checksum format.

    :returns: A JSON response with keys ``address``, ``network``, ``blockTag``,
              ``balance`` (Ether as string), ``balanceWei`` (Wei as string),
              and ``headBlockNumber`` (hex block number).
    :raises fastapi.HTTPException: 400 for invalid input; 502 for upstream
                                   provider errors; 500 for unexpected errors.
    """
    # Enforce 0x prefix and EIP-55 checksum strictly
    if not (address.startswith("0x") and is_checksum_address(address)):
        raise HTTPException(status_code=400, detail="Address must be 0x-prefixed and EIP-55 checksummed")

    checksum_address = address  # already validated
    network = "mainnet"
    tag = "latest"
    rpc_url = get_infura_rpc_url_mainnet()

    # Cache lookup
    cached = _cache.get(checksum_address)
    if cached and cached[0] > _now():
        return cached[1]

    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_getBalance",
        "params": [checksum_address, tag],
    }

    try:
        with httpx.Client(timeout=8.0) as client:
            rpc_resp = client.post(rpc_url, json=payload, headers={"Content-Type": "application/json"})
            data = rpc_resp.json()
            if "error" in data:
                raise HTTPException(status_code=502, detail={"upstream_error": data["error"]})
            result_hex = data.get("result")
            if not isinstance(result_hex, str):
                raise HTTPException(status_code=502, detail="Bad upstream response")
            wei = int(result_hex, 16)

            # Optional: fetch current head block number
            bn_resp = client.post(rpc_url, json={"jsonrpc": "2.0", "id": 2, "method": "eth_blockNumber", "params": []}, headers={"Content-Type": "application/json"})
            head_hex = bn_resp.json().get("result")

        response = {
            "address": checksum_address,
            "network": network,
            "blockTag": tag,
            "balance": str(Web3.from_wei(wei, 'ether')),
            "balanceWei": str(wei),
            "headBlockNumber": head_hex or None,
        }
        # Update cache
        _cache[checksum_address] = (_now() + CACHE_TTL_SECONDS, response)
        return response
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


