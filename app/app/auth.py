from fastapi import Request, HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
import httpx
from .config import settings
from functools import lru_cache

bearer = HTTPBearer(auto_error=False)

@lru_cache()
def _fetch_jwks():
    r = httpx.get(settings.COGNITO_JWKS_URL, timeout=5.0)
    r.raise_for_status()
    return r.json()

def validate_jwt(token: str) -> dict:
    jwks = _fetch_jwks()
    try:
        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        key = next(k for k in jwks["keys"] if k["kid"] == kid)
        public_key = jwt.construct_rsa_public_key(key)
        payload = jwt.decode(token, public_key, algorithms=[header.get("alg", "RS256")], audience=settings.COGNITO_USERPOOL_AUD)
        return payload
    except Exception as e:
        raise JWTError from e

async def require_auth(credentials: HTTPAuthorizationCredentials = Security(bearer)):
    if not credentials:
        raise HTTPException(status_code=401, detail="Missing authorization")
    token = credentials.credentials
    try:
        claims = validate_jwt(token)
        return claims
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")