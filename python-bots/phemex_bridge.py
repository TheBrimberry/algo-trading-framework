#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════╗
║          JazzyLyfe Phemex-MT5 Bridge Server v1.0                ║
║          Async FastAPI relay: MT5 EA → Phemex Exchange           ║
║          Supports: Spot, Contract, Hedged Perpetual              ║
║          Auth: HMAC-SHA256 | WebSocket streaming                 ║
╚══════════════════════════════════════════════════════════════════╝

Usage:
    python phemex_bridge.py
    # or via uvicorn:
    uvicorn phemex_bridge:app --host 0.0.0.0 --port 8599
"""

import asyncio
import hashlib
import hmac
import json
import logging
import os
import sys
import time
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# ─── Load Environment ────────────────────────────────────────────
load_dotenv()

# ─── Logging ─────────────────────────────────────────────────────
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s │ %(levelname)-8s │ %(name)s │ %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("bridge.log", mode="a"),
    ],
)
logger = logging.getLogger("PhemexBridge")


# ═══════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════
class Config:
    """Bridge configuration loaded from environment variables."""

    PHEMEX_API_KEY: str = os.getenv("PHEMEX_API_KEY", "")
    PHEMEX_API_SECRET: str = os.getenv("PHEMEX_API_SECRET", "")
    PHEMEX_TESTNET: bool = os.getenv("PHEMEX_TESTNET", "true").lower() == "true"

    # Endpoints
    MAINNET_REST: str = "https://api.phemex.com"
    TESTNET_REST: str = "https://testnet-api.phemex.com"
    MAINNET_WS: str = "wss://ws.phemex.com"
    TESTNET_WS: str = "wss://testnet-api.phemex.com/ws"

    # Bridge settings
    BRIDGE_HOST: str = os.getenv("BRIDGE_HOST", "0.0.0.0")
    BRIDGE_PORT: int = int(os.getenv("BRIDGE_PORT", "8599"))
    BRIDGE_SECRET: str = os.getenv("BRIDGE_SECRET", "")  # Optional local auth

    # Risk management
    MAX_POSITION_SIZE_USD: float = float(os.getenv("MAX_POSITION_SIZE_USD", "10000"))
    MAX_DAILY_TRADES: int = int(os.getenv("MAX_DAILY_TRADES", "100"))
    MAX_DAILY_LOSS_USD: float = float(os.getenv("MAX_DAILY_LOSS_USD", "500"))
    DEFAULT_LEVERAGE: int = int(os.getenv("DEFAULT_LEVERAGE", "5"))
    RISK_PER_TRADE_PCT: float = float(os.getenv("RISK_PER_TRADE_PCT", "2.0"))

    @property
    def rest_url(self) -> str:
        return self.TESTNET_REST if self.PHEMEX_TESTNET else self.MAINNET_REST

    @property
    def ws_url(self) -> str:
        return self.TESTNET_WS if self.PHEMEX_TESTNET else self.MAINNET_WS

    @property
    def env_label(self) -> str:
        return "TESTNET" if self.PHEMEX_TESTNET else "MAINNET (LIVE)"


config = Config()


# ═══════════════════════════════════════════════════════════════════
# ENUMS & MODELS
# ═══════════════════════════════════════════════════════════════════
class OrderSide(str, Enum):
    BUY = "Buy"
    SELL = "Sell"


class OrderType(str, Enum):
    MARKET = "Market"
    LIMIT = "Limit"
    STOP = "Stop"
    STOP_LIMIT = "StopLimit"


class TimeInForce(str, Enum):
    GTC = "GoodTillCancel"
    IOC = "ImmediateOrCancel"
    FOK = "FillOrKill"
    POST_ONLY = "PostOnly"


class MarketType(str, Enum):
    SPOT = "spot"
    CONTRACT = "contract"
    HEDGED = "hedged"


class PosSide(str, Enum):
    LONG = "Long"
    SHORT = "Short"
    MERGED = "Merged"


# ─── Request Models ──────────────────────────────────────────────
class OrderRequest(BaseModel):
    """Order request from MT5 EA."""
    symbol: str = Field(..., description="Trading symbol, e.g. BTCUSD, sBTCUSDT")
    side: OrderSide = Field(..., description="Buy or Sell")
    order_type: OrderType = Field(default=OrderType.MARKET, description="Order type")
    quantity: float = Field(..., gt=0, description="Order quantity")
    price: Optional[float] = Field(None, description="Limit price (required for Limit orders)")
    stop_price: Optional[float] = Field(None, description="Stop trigger price")
    market_type: MarketType = Field(default=MarketType.CONTRACT, description="spot, contract, or hedged")
    leverage: Optional[int] = Field(None, ge=1, le=100, description="Leverage for contracts")
    reduce_only: bool = Field(default=False, description="Reduce-only order")
    time_in_force: TimeInForce = Field(default=TimeInForce.GTC, description="Time in force")
    take_profit: Optional[float] = Field(None, description="Take profit price")
    stop_loss: Optional[float] = Field(None, description="Stop loss price")
    pos_side: Optional[PosSide] = Field(None, description="Position side for hedged mode")
    client_order_id: Optional[str] = Field(None, description="Client order ID from EA")
    text: Optional[str] = Field(None, description="Order comment/tag")


class CancelRequest(BaseModel):
    """Cancel order request."""
    symbol: str
    order_id: Optional[str] = None
    client_order_id: Optional[str] = None
    market_type: MarketType = Field(default=MarketType.CONTRACT)


class CancelAllRequest(BaseModel):
    """Cancel all orders for a symbol."""
    symbol: str
    market_type: MarketType = Field(default=MarketType.CONTRACT)


class AmendRequest(BaseModel):
    """Amend order request."""
    symbol: str
    order_id: Optional[str] = None
    client_order_id: Optional[str] = None
    price: Optional[float] = None
    quantity: Optional[float] = None
    stop_price: Optional[float] = None
    market_type: MarketType = Field(default=MarketType.CONTRACT)


class PositionRequest(BaseModel):
    """Query position request."""
    symbol: Optional[str] = None
    currency: str = Field(default="USD")
    market_type: MarketType = Field(default=MarketType.CONTRACT)


class LeverageRequest(BaseModel):
    """Set leverage request."""
    symbol: str
    leverage: int = Field(ge=1, le=100)
    market_type: MarketType = Field(default=MarketType.CONTRACT)


# ═══════════════════════════════════════════════════════════════════
# PHEMEX API CLIENT
# ═══════════════════════════════════════════════════════════════════
class PhemexClient:
    """Async Phemex REST API client with HMAC-SHA256 authentication."""

    def __init__(self):
        self.api_key = config.PHEMEX_API_KEY
        self.api_secret = config.PHEMEX_API_SECRET
        self.base_url = config.rest_url
        self._client: Optional[httpx.AsyncClient] = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=self.base_url,
                timeout=httpx.Timeout(30.0, connect=10.0),
                limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
            )
        return self._client

    async def close(self):
        if self._client and not self._client.is_closed:
            await self._client.aclose()

    def _sign(self, path: str, query_string: str, expiry: int, body: str = "") -> str:
        """Generate HMAC-SHA256 signature for Phemex API."""
        message = f"{path}{query_string}{expiry}{body}"
        signature = hmac.new(
            self.api_secret.encode("utf-8"),
            message.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return signature

    def _headers(self, path: str, query_string: str = "", body: str = "") -> Dict[str, str]:
        """Build authenticated request headers."""
        expiry = int(time.time()) + 60
        signature = self._sign(path, query_string, expiry, body)
        return {
            "x-phemex-access-token": self.api_key,
            "x-phemex-request-expiry": str(expiry),
            "x-phemex-request-signature": signature,
            "x-phemex-request-tracing": str(uuid.uuid4())[:36],
            "Content-Type": "application/json",
        }

    async def _request(
        self,
        method: str,
        path: str,
        params: Optional[Dict] = None,
        data: Optional[Dict] = None,
    ) -> Dict[str, Any]:
        """Execute authenticated API request."""
        client = await self._get_client()

        query_string = ""
        if params:
            query_string = "&".join(f"{k}={v}" for k, v in sorted(params.items()))

        body = ""
        if data:
            body = json.dumps(data, separators=(",", ":"))

        headers = self._headers(path, query_string, body)

        url = path
        if query_string:
            url = f"{path}?{query_string}"

        try:
            if method == "GET":
                resp = await client.get(url, headers=headers)
            elif method == "POST":
                resp = await client.post(url, headers=headers, content=body)
            elif method == "PUT":
                resp = await client.put(url, headers=headers, content=body)
            elif method == "DELETE":
                if body:
                    resp = await client.request("DELETE", url, headers=headers, content=body)
                else:
                    resp = await client.delete(url, headers=headers)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")

            result = resp.json()

            # Log rate limit headers
            remaining = resp.headers.get("x-ratelimit-remaining-contract", "N/A")
            logger.debug(f"Rate limit remaining: {remaining}")

            if resp.status_code == 429:
                retry_after = resp.headers.get("x-ratelimit-retry-after-contract", "60")
                logger.warning(f"Rate limited! Retry after {retry_after}s")
                raise HTTPException(status_code=429, detail=f"Phemex rate limit. Retry after {retry_after}s")

            if resp.status_code == 401:
                raise HTTPException(status_code=401, detail="Phemex authentication failed. Check API keys.")

            if result.get("code", 0) != 0:
                logger.error(f"Phemex API error: {result}")
                raise HTTPException(
                    status_code=400,
                    detail=f"Phemex error {result.get('code')}: {result.get('msg', 'Unknown error')}",
                )

            return result

        except httpx.RequestError as e:
            logger.error(f"HTTP request failed: {e}")
            raise HTTPException(status_code=502, detail=f"Connection to Phemex failed: {str(e)}")

    # ─── Contract Orders ─────────────────────────────────────────
    async def place_contract_order(self, order: OrderRequest) -> Dict:
        """Place a contract (perpetual) order."""
        payload: Dict[str, Any] = {
            "symbol": order.symbol,
            "clOrdID": order.client_order_id or f"mt5-{uuid.uuid4().hex[:16]}",
            "side": order.side.value,
            "orderQty": order.quantity,
            "ordType": order.order_type.value,
            "reduceOnly": order.reduce_only,
            "timeInForce": order.time_in_force.value,
        }

        if order.price and order.order_type in (OrderType.LIMIT, OrderType.STOP_LIMIT):
            payload["priceRp"] = str(order.price)

        if order.stop_price:
            payload["stopPxRp"] = str(order.stop_price)

        if order.take_profit:
            payload["takeProfitRp"] = str(order.take_profit)

        if order.stop_loss:
            payload["stopLossRp"] = str(order.stop_loss)

        if order.text:
            payload["text"] = order.text

        logger.info(f"[CONTRACT] Placing order: {order.side.value} {order.quantity} {order.symbol}")
        return await self._request("POST", "/orders", data=payload)

    # ─── Hedged Perpetual Orders ─────────────────────────────────
    async def place_hedged_order(self, order: OrderRequest) -> Dict:
        """Place a hedged perpetual order (supports simultaneous long/short)."""
        payload: Dict[str, Any] = {
            "symbol": order.symbol,
            "clOrdID": order.client_order_id or f"mt5-{uuid.uuid4().hex[:16]}",
            "side": order.side.value,
            "orderQty": order.quantity,
            "ordType": order.order_type.value,
            "reduceOnly": order.reduce_only,
            "timeInForce": order.time_in_force.value,
            "posSide": (order.pos_side or PosSide.LONG).value,
        }

        if order.price and order.order_type in (OrderType.LIMIT, OrderType.STOP_LIMIT):
            payload["priceRp"] = str(order.price)

        if order.stop_price:
            payload["stopPxRp"] = str(order.stop_price)

        if order.take_profit:
            payload["takeProfitRp"] = str(order.take_profit)

        if order.stop_loss:
            payload["stopLossRp"] = str(order.stop_loss)

        if order.text:
            payload["text"] = order.text

        logger.info(
            f"[HEDGED] Placing order: {order.side.value} {order.quantity} {order.symbol} "
            f"posSide={payload['posSide']}"
        )
        return await self._request("POST", "/g-orders/create", data=payload)

    # ─── Spot Orders ─────────────────────────────────────────────
    async def place_spot_order(self, order: OrderRequest) -> Dict:
        """Place a spot order."""
        payload: Dict[str, Any] = {
            "symbol": order.symbol,
            "clOrdID": order.client_order_id or f"mt5-{uuid.uuid4().hex[:16]}",
            "side": order.side.value,
            "ordType": order.order_type.value,
            "qtyType": "ByBase",
            "baseQtyEv": int(order.quantity * 1e8),
            "timeInForce": order.time_in_force.value,
        }

        if order.price and order.order_type == OrderType.LIMIT:
            payload["priceEp"] = int(order.price * 1e8)

        if order.text:
            payload["text"] = order.text

        logger.info(f"[SPOT] Placing order: {order.side.value} {order.quantity} {order.symbol}")
        return await self._request("POST", "/spot/orders/create", data=payload)

    # ─── Cancel Orders ───────────────────────────────────────────
    async def cancel_order(self, req: CancelRequest) -> Dict:
        """Cancel a specific order."""
        params: Dict[str, str] = {"symbol": req.symbol}
        if req.order_id:
            params["orderID"] = req.order_id
        if req.client_order_id:
            params["clOrdID"] = req.client_order_id

        if req.market_type == MarketType.SPOT:
            path = "/spot/orders/cancel"
        elif req.market_type == MarketType.HEDGED:
            path = "/g-orders/cancel"
        else:
            path = "/orders/cancel"

        logger.info(f"[{req.market_type.value.upper()}] Cancelling order on {req.symbol}")
        return await self._request("DELETE", path, params=params)

    async def cancel_all_orders(self, req: CancelAllRequest) -> Dict:
        """Cancel all orders for a symbol."""
        params = {"symbol": req.symbol}

        if req.market_type == MarketType.SPOT:
            path = "/spot/orders/all"
        elif req.market_type == MarketType.HEDGED:
            path = "/g-orders"
        else:
            path = "/orders/all"

        logger.info(f"[{req.market_type.value.upper()}] Cancelling ALL orders on {req.symbol}")
        return await self._request("DELETE", path, params=params)

    # ─── Amend Orders ────────────────────────────────────────────
    async def amend_order(self, req: AmendRequest) -> Dict:
        """Amend an existing order."""
        payload: Dict[str, Any] = {"symbol": req.symbol}

        if req.order_id:
            payload["orderID"] = req.order_id
        if req.client_order_id:
            payload["clOrdID"] = req.client_order_id
        if req.price is not None:
            payload["priceRp"] = str(req.price)
        if req.quantity is not None:
            payload["orderQty"] = req.quantity
        if req.stop_price is not None:
            payload["stopPxRp"] = str(req.stop_price)

        if req.market_type == MarketType.SPOT:
            path = "/spot/orders/amend"
        elif req.market_type == MarketType.HEDGED:
            path = "/g-orders/replace"
        else:
            path = "/orders/replace"

        logger.info(f"[{req.market_type.value.upper()}] Amending order on {req.symbol}")
        return await self._request("PUT", path, data=payload)

    # ─── Query Positions ─────────────────────────────────────────
    async def get_positions(self, req: PositionRequest) -> Dict:
        """Query account positions."""
        params = {"currency": req.currency}

        if req.market_type == MarketType.HEDGED:
            path = "/g-accounts/accountPositions"
        else:
            path = "/accounts/accountPositions"

        return await self._request("GET", path, params=params)

    # ─── Query Open Orders ───────────────────────────────────────
    async def get_open_orders(self, symbol: str, market_type: MarketType = MarketType.CONTRACT) -> Dict:
        """Query open orders for a symbol."""
        params = {"symbol": symbol}

        if market_type == MarketType.SPOT:
            path = "/spot/orders/active"
        elif market_type == MarketType.HEDGED:
            path = "/g-orders/activeList"
        else:
            path = "/orders/activeList"

        return await self._request("GET", path, params=params)

    # ─── Set Leverage ────────────────────────────────────────────
    async def set_leverage(self, req: LeverageRequest) -> Dict:
        """Set leverage for a symbol."""
        payload = {
            "symbol": req.symbol,
            "leverageRr": str(req.leverage),
        }

        if req.market_type == MarketType.HEDGED:
            path = "/g-positions/leverage"
        else:
            path = "/positions/leverage"

        logger.info(f"Setting leverage for {req.symbol} to {req.leverage}x")
        return await self._request("PUT", path, data=payload)

    # ─── Query Wallets ───────────────────────────────────────────
    async def get_spot_wallets(self) -> Dict:
        """Query spot wallets."""
        return await self._request("GET", "/spot/wallets")

    # ─── Query Ticker ────────────────────────────────────────────
    async def get_ticker(self, symbol: str) -> Dict:
        """Get 24h ticker for a symbol (public, no auth needed)."""
        client = await self._get_client()
        resp = await client.get(f"/md/v2/ticker/24hr?symbol={symbol}")
        return resp.json()


# ═══════════════════════════════════════════════════════════════════
# RISK MANAGER
# ═══════════════════════════════════════════════════════════════════
class RiskManager:
    """Trade risk management and daily limits tracking."""

    def __init__(self):
        self.daily_trades: int = 0
        self.daily_pnl: float = 0.0
        self.last_reset: str = ""
        self.trade_log: List[Dict] = []
        self._reset_if_new_day()

    def _reset_if_new_day(self):
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        if today != self.last_reset:
            self.daily_trades = 0
            self.daily_pnl = 0.0
            self.trade_log = []
            self.last_reset = today
            logger.info(f"Risk manager reset for new day: {today}")

    def check_order(self, order: OrderRequest) -> tuple[bool, str]:
        """Validate order against risk limits. Returns (allowed, reason)."""
        self._reset_if_new_day()

        # Check daily trade count
        if self.daily_trades >= config.MAX_DAILY_TRADES:
            return False, f"Daily trade limit reached ({config.MAX_DAILY_TRADES})"

        # Check daily loss limit
        if self.daily_pnl <= -config.MAX_DAILY_LOSS_USD:
            return False, f"Daily loss limit reached (${config.MAX_DAILY_LOSS_USD})"

        # Check position size (for market orders without price, use quantity directly as USD notional)
        if order.price:
            notional = order.quantity * order.price
        else:
            notional = order.quantity
        if notional > config.MAX_POSITION_SIZE_USD:
            return False, f"Position size ${notional:.2f} exceeds max ${config.MAX_POSITION_SIZE_USD}"

        return True, "OK"

    def update_pnl(self, pnl: float):
        """Update daily PnL from closed trade result."""
        self._reset_if_new_day()
        self.daily_pnl += pnl
        logger.info(f"Daily PnL updated: {self.daily_pnl:+.2f}")

    def record_trade(self, order: OrderRequest, result: Dict):
        """Record a completed trade."""
        self._reset_if_new_day()
        self.daily_trades += 1
        self.trade_log.append({
            "time": datetime.now(timezone.utc).isoformat(),
            "symbol": order.symbol,
            "side": order.side.value,
            "quantity": order.quantity,
            "type": order.order_type.value,
            "market": order.market_type.value,
        })
        logger.info(f"Trade #{self.daily_trades} recorded: {order.side.value} {order.quantity} {order.symbol}")

    def get_stats(self) -> Dict:
        """Get current risk stats."""
        self._reset_if_new_day()
        return {
            "date": self.last_reset,
            "daily_trades": self.daily_trades,
            "max_daily_trades": config.MAX_DAILY_TRADES,
            "daily_pnl": self.daily_pnl,
            "max_daily_loss": config.MAX_DAILY_LOSS_USD,
            "max_position_size": config.MAX_POSITION_SIZE_USD,
            "recent_trades": self.trade_log[-10:],
        }


# ═══════════════════════════════════════════════════════════════════
# WEBSOCKET MANAGER
# ═══════════════════════════════════════════════════════════════════
class WebSocketManager:
    """Manages WebSocket connection to Phemex for real-time data streaming."""

    def __init__(self):
        self._ws = None
        self._running = False
        self._subscriptions: Dict[str, set] = defaultdict(set)
        self._latest_data: Dict[str, Any] = {}
        self._task: Optional[asyncio.Task] = None

    async def connect(self):
        """Establish WebSocket connection to Phemex."""
        try:
            import websockets
            self._ws = await websockets.connect(
                config.ws_url,
                ping_interval=20,
                ping_timeout=10,
                close_timeout=5,
            )
            self._running = True
            logger.info(f"WebSocket connected to {config.ws_url}")

            # Authenticate
            expiry = int(time.time()) + 120
            signature = hmac.new(
                config.PHEMEX_API_SECRET.encode(),
                f"/realtime{expiry}".encode(),
                hashlib.sha256,
            ).hexdigest()

            auth_msg = {
                "method": "user.auth",
                "params": ["API", config.PHEMEX_API_KEY, signature, expiry],
                "id": 1,
            }
            await self._ws.send(json.dumps(auth_msg))
            resp = await asyncio.wait_for(self._ws.recv(), timeout=10)
            logger.info(f"WebSocket auth response: {resp}")

            # Start listener
            self._task = asyncio.create_task(self._listen())

        except ImportError:
            logger.warning("websockets package not installed. WebSocket streaming disabled.")
            logger.warning("Install with: pip install websockets")
        except Exception as e:
            logger.error(f"WebSocket connection failed: {e}")

    async def _listen(self):
        """Listen for incoming WebSocket messages."""
        try:
            while self._running and self._ws:
                try:
                    msg = await asyncio.wait_for(self._ws.recv(), timeout=30)
                    data = json.loads(msg)

                    # Handle heartbeat
                    if "ping" in str(data).lower():
                        await self._ws.send(json.dumps({"method": "server.ping", "id": 0, "params": []}))
                        continue

                    # Store latest data by topic
                    if "type" in data:
                        topic = data.get("topic", "unknown")
                        self._latest_data[topic] = data
                        logger.debug(f"WS data: {topic}")

                except asyncio.TimeoutError:
                    # Send ping to keep alive
                    if self._ws:
                        await self._ws.send(json.dumps({"method": "server.ping", "id": 0, "params": []}))
                except Exception as e:
                    logger.error(f"WebSocket listener error: {e}")
                    break

        except Exception as e:
            logger.error(f"WebSocket listener crashed: {e}")
        finally:
            self._running = False

    async def subscribe_orderbook(self, symbol: str):
        """Subscribe to orderbook updates."""
        if self._ws and self._running:
            msg = {
                "method": "orderbook_p.subscribe",
                "params": [symbol],
                "id": int(time.time()),
            }
            await self._ws.send(json.dumps(msg))
            logger.info(f"Subscribed to orderbook: {symbol}")

    async def subscribe_trades(self, symbol: str):
        """Subscribe to trade updates."""
        if self._ws and self._running:
            msg = {
                "method": "trade_p.subscribe",
                "params": [symbol],
                "id": int(time.time()),
            }
            await self._ws.send(json.dumps(msg))
            logger.info(f"Subscribed to trades: {symbol}")

    async def subscribe_account(self):
        """Subscribe to account and order updates."""
        if self._ws and self._running:
            msg = {
                "method": "wo.subscribe",
                "params": [],
                "id": int(time.time()),
            }
            await self._ws.send(json.dumps(msg))
            logger.info("Subscribed to account updates")

    async def subscribe_kline(self, symbol: str, interval: int = 60):
        """Subscribe to kline/candlestick updates."""
        if self._ws and self._running:
            msg = {
                "method": "kline_p.subscribe",
                "params": [symbol, interval],
                "id": int(time.time()),
            }
            await self._ws.send(json.dumps(msg))
            logger.info(f"Subscribed to kline: {symbol} ({interval}s)")

    def get_latest(self, topic: str) -> Optional[Dict]:
        """Get latest data for a topic."""
        return self._latest_data.get(topic)

    async def disconnect(self):
        """Disconnect WebSocket."""
        self._running = False
        if self._task:
            self._task.cancel()
        if self._ws:
            await self._ws.close()
            logger.info("WebSocket disconnected")


# ═══════════════════════════════════════════════════════════════════
# FASTAPI APPLICATION
# ═══════════════════════════════════════════════════════════════════
app = FastAPI(
    title="JazzyLyfe Phemex-MT5 Bridge",
    description="Relay server bridging MetaTrader 5 Expert Advisors to Phemex Exchange",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global instances
phemex = PhemexClient()
risk_mgr = RiskManager()
ws_mgr = WebSocketManager()


# ─── Middleware: Optional Bridge Auth ────────────────────────────
@app.middleware("http")
async def bridge_auth_middleware(request: Request, call_next):
    """Optional authentication for the bridge itself."""
    if config.BRIDGE_SECRET:
        # Skip auth for docs and health endpoints
        if request.url.path in ("/", "/health", "/docs", "/redoc", "/openapi.json"):
            return await call_next(request)

        auth_header = request.headers.get("X-Bridge-Secret", "")
        if auth_header != config.BRIDGE_SECRET:
            return JSONResponse(
                status_code=401,
                content={"error": "Invalid bridge secret"},
            )

    return await call_next(request)


# ─── Startup / Shutdown ─────────────────────────────────────────
@app.on_event("startup")
async def startup():
    logger.info("=" * 60)
    logger.info("  JazzyLyfe Phemex-MT5 Bridge v1.0")
    logger.info(f"  Environment: {config.env_label}")
    logger.info(f"  REST URL: {config.rest_url}")
    logger.info(f"  Bridge: http://{config.BRIDGE_HOST}:{config.BRIDGE_PORT}")
    logger.info(f"  API Key: {config.PHEMEX_API_KEY[:8]}..." if config.PHEMEX_API_KEY else "  API Key: NOT SET")
    logger.info(f"  Max Position: ${config.MAX_POSITION_SIZE_USD:,.0f}")
    logger.info(f"  Max Daily Trades: {config.MAX_DAILY_TRADES}")
    logger.info(f"  Max Daily Loss: ${config.MAX_DAILY_LOSS_USD:,.0f}")
    logger.info("=" * 60)

    if not config.PHEMEX_API_KEY or not config.PHEMEX_API_SECRET:
        logger.warning("⚠ Phemex API keys not configured! Set them in .env file.")

    # Start WebSocket connection
    try:
        await ws_mgr.connect()
    except Exception as e:
        logger.warning(f"WebSocket startup skipped: {e}")


@app.on_event("shutdown")
async def shutdown():
    await phemex.close()
    await ws_mgr.disconnect()
    logger.info("Bridge shutdown complete.")


# ═══════════════════════════════════════════════════════════════════
# API ENDPOINTS
# ═══════════════════════════════════════════════════════════════════

# ─── Health & Status ─────────────────────────────────────────────
@app.get("/", tags=["Status"])
async def root():
    """Bridge root — confirms the server is running."""
    return {
        "service": "JazzyLyfe Phemex-MT5 Bridge",
        "version": "1.0.0",
        "environment": config.env_label,
        "status": "running",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/health", tags=["Status"])
async def health():
    """Health check endpoint for monitoring."""
    api_configured = bool(config.PHEMEX_API_KEY and config.PHEMEX_API_SECRET)
    return {
        "status": "healthy",
        "api_configured": api_configured,
        "environment": config.env_label,
        "risk_stats": risk_mgr.get_stats(),
        "ws_connected": ws_mgr._running,
        "uptime": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/risk", tags=["Risk Management"])
async def get_risk_stats():
    """Get current risk management statistics."""
    return {"status": "ok", "data": risk_mgr.get_stats()}


# ─── Order Placement ────────────────────────────────────────────
@app.post("/order", tags=["Trading"])
async def place_order(order: OrderRequest):
    """
    Place an order on Phemex.
    Routes to spot, contract, or hedged perpetual based on market_type.
    """
    # Risk check
    allowed, reason = risk_mgr.check_order(order)
    if not allowed:
        logger.warning(f"Order REJECTED by risk manager: {reason}")
        raise HTTPException(status_code=403, detail=f"Risk limit: {reason}")

    # Route to appropriate market
    try:
        if order.market_type == MarketType.SPOT:
            result = await phemex.place_spot_order(order)
        elif order.market_type == MarketType.HEDGED:
            result = await phemex.place_hedged_order(order)
        else:
            result = await phemex.place_contract_order(order)

        # Record trade
        risk_mgr.record_trade(order, result)

        return {
            "status": "ok",
            "market_type": order.market_type.value,
            "data": result.get("data", result),
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Order placement failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ─── Quick Market Order (simplified for EA) ──────────────────────
@app.post("/quick_order", tags=["Trading"])
async def quick_order(
    symbol: str,
    side: str,
    quantity: float,
    market_type: str = "contract",
    leverage: Optional[int] = None,
    take_profit: Optional[float] = None,
    stop_loss: Optional[float] = None,
    pos_side: Optional[str] = None,
):
    """
    Simplified market order endpoint for MT5 EA.
    Accepts query-style parameters for easy WebRequest integration.
    """
    order = OrderRequest(
        symbol=symbol,
        side=OrderSide(side),
        order_type=OrderType.MARKET,
        quantity=quantity,
        market_type=MarketType(market_type),
        leverage=leverage,
        take_profit=take_profit,
        stop_loss=stop_loss,
        pos_side=PosSide(pos_side) if pos_side else None,
    )
    return await place_order(order)


# ─── Cancel Orders ───────────────────────────────────────────────
@app.post("/cancel", tags=["Trading"])
async def cancel_order(req: CancelRequest):
    """Cancel a specific order."""
    result = await phemex.cancel_order(req)
    return {"status": "ok", "data": result.get("data", result)}


@app.post("/cancel_all", tags=["Trading"])
async def cancel_all(req: CancelAllRequest):
    """Cancel all orders for a symbol."""
    result = await phemex.cancel_all_orders(req)
    return {"status": "ok", "data": result.get("data", result)}


# ─── Amend Orders ────────────────────────────────────────────────
@app.post("/amend", tags=["Trading"])
async def amend_order(req: AmendRequest):
    """Amend an existing order."""
    result = await phemex.amend_order(req)
    return {"status": "ok", "data": result.get("data", result)}


# ─── Positions ───────────────────────────────────────────────────
@app.post("/positions", tags=["Account"])
async def get_positions(req: PositionRequest):
    """Query account positions."""
    result = await phemex.get_positions(req)
    return {"status": "ok", "data": result.get("data", result)}


@app.get("/positions/{currency}", tags=["Account"])
async def get_positions_simple(currency: str = "USD", market_type: str = "contract"):
    """Simplified position query for EA."""
    req = PositionRequest(currency=currency, market_type=MarketType(market_type))
    result = await phemex.get_positions(req)
    return {"status": "ok", "data": result.get("data", result)}


# ─── Open Orders ─────────────────────────────────────────────────
@app.get("/orders/{symbol}", tags=["Trading"])
async def get_open_orders(symbol: str, market_type: str = "contract"):
    """Query open orders for a symbol."""
    result = await phemex.get_open_orders(symbol, MarketType(market_type))
    return {"status": "ok", "data": result.get("data", result)}


# ─── Leverage ────────────────────────────────────────────────────
@app.post("/leverage", tags=["Account"])
async def set_leverage(req: LeverageRequest):
    """Set leverage for a symbol."""
    result = await phemex.set_leverage(req)
    return {"status": "ok", "data": result.get("data", result)}


@app.get("/leverage/{symbol}/{leverage}", tags=["Account"])
async def set_leverage_simple(symbol: str, leverage: int, market_type: str = "contract"):
    """Simplified leverage setting for EA."""
    req = LeverageRequest(symbol=symbol, leverage=leverage, market_type=MarketType(market_type))
    result = await phemex.set_leverage(req)
    return {"status": "ok", "data": result.get("data", result)}


# ─── Wallets ─────────────────────────────────────────────────────
@app.get("/wallets", tags=["Account"])
async def get_wallets():
    """Query spot wallets."""
    result = await phemex.get_spot_wallets()
    return {"status": "ok", "data": result.get("data", result)}


# ─── Market Data ─────────────────────────────────────────────────
@app.get("/ticker/{symbol}", tags=["Market Data"])
async def get_ticker(symbol: str):
    """Get 24h ticker for a symbol."""
    result = await phemex.get_ticker(symbol)
    return {"status": "ok", "data": result.get("result", result)}


# ─── WebSocket Management ────────────────────────────────────────
@app.post("/ws/subscribe", tags=["WebSocket"])
async def ws_subscribe(symbol: str, channel: str = "orderbook"):
    """Subscribe to a WebSocket channel."""
    if channel == "orderbook":
        await ws_mgr.subscribe_orderbook(symbol)
    elif channel == "trades":
        await ws_mgr.subscribe_trades(symbol)
    elif channel == "kline":
        await ws_mgr.subscribe_kline(symbol)
    elif channel == "account":
        await ws_mgr.subscribe_account()
    else:
        raise HTTPException(status_code=400, detail=f"Unknown channel: {channel}")

    return {"status": "ok", "subscribed": f"{channel}:{symbol}"}


@app.get("/ws/data/{topic}", tags=["WebSocket"])
async def ws_get_data(topic: str):
    """Get latest WebSocket data for a topic."""
    data = ws_mgr.get_latest(topic)
    return {"status": "ok", "data": data}


# ─── Batch Operations ────────────────────────────────────────────
@app.post("/batch/orders", tags=["Trading"])
async def batch_orders(orders: List[OrderRequest]):
    """Place multiple orders in sequence."""
    results = []
    for i, order in enumerate(orders):
        try:
            result = await place_order(order)
            results.append({"index": i, "status": "ok", "data": result})
        except HTTPException as e:
            results.append({"index": i, "status": "error", "detail": e.detail})
        except Exception as e:
            results.append({"index": i, "status": "error", "detail": str(e)})

    return {"status": "ok", "results": results}


# ─── Close Position ──────────────────────────────────────────────
@app.post("/close_position", tags=["Trading"])
async def close_position(
    symbol: str,
    side: str,
    quantity: float,
    market_type: str = "contract",
    pos_side: Optional[str] = None,
):
    """
    Close a position (convenience endpoint).
    Sends a reduce-only market order in the opposite direction.
    """
    # Flip the side for closing
    close_side = OrderSide.SELL if side == "Buy" else OrderSide.BUY

    order = OrderRequest(
        symbol=symbol,
        side=close_side,
        order_type=OrderType.MARKET,
        quantity=quantity,
        market_type=MarketType(market_type),
        reduce_only=True,
        pos_side=PosSide(pos_side) if pos_side else None,
    )
    return await place_order(order)


# ═══════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ═══════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    import uvicorn

    print(r"""
    ╔══════════════════════════════════════════════════════════╗
    ║       JazzyLyfe Phemex-MT5 Bridge v1.0                  ║
    ║       Starting on http://0.0.0.0:8599                   ║
    ║       Docs: http://127.0.0.1:8599/docs                  ║
    ╚══════════════════════════════════════════════════════════╝
    """)

    uvicorn.run(
        "phemex_bridge:app",
        host=config.BRIDGE_HOST,
        port=config.BRIDGE_PORT,
        reload=False,
        log_level=LOG_LEVEL.lower(),
        access_log=True,
    )
