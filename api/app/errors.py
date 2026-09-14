"""Structured, leak-free errors.

Every failure the API returns looks like:

    {"error": {"code": "machine_readable_code",
               "message": "safe human message",
               "details": [...] }}

Internals (tracebacks, SQL, secrets) are logged server-side only.
"""

import logging
import uuid

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

log = logging.getLogger("phonicsai.api")


class AppError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = status.HTTP_400_BAD_REQUEST,
        details: list | None = None,
    ) -> None:
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details
        super().__init__(message)


def not_found(msg: str = "Resource not found") -> AppError:
    return AppError("not_found", msg, status.HTTP_404_NOT_FOUND)


def forbidden(msg: str = "Not permitted") -> AppError:
    return AppError("forbidden", msg, status.HTTP_403_FORBIDDEN)


def unauthorized(msg: str = "Authentication required") -> AppError:
    return AppError("unauthorized", msg, status.HTTP_401_UNAUTHORIZED)


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        body: dict = {"error": {"code": exc.code, "message": exc.message}}
        if exc.details:
            body["error"]["details"] = exc.details
        return JSONResponse(status_code=exc.status_code, content=body)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        details = [
            {"field": ".".join(str(p) for p in err["loc"][1:]) or "body", "issue": err["msg"]}
            for err in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content={"error": {"code": "validation_failed",
                              "message": "Request failed validation",
                              "details": details}},
        )

    @app.exception_handler(RateLimitExceeded)
    async def _rate_limited(request: Request, exc: RateLimitExceeded) -> JSONResponse:
        return _rate_limit_exceeded_handler(request, exc)

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        request_id = uuid.uuid4().hex[:12]
        log.exception("unhandled error (request_id=%s)", request_id)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={"error": {"code": "internal_error",
                              "message": "The server could not complete the request. "
                                         f"Reference: {request_id}"}},
        )
