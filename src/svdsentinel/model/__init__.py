"""Normalized, vendor-independent device model.

These pydantic models are the only representation of SVD data that the rest
of svdsentinel is allowed to touch. Nothing downstream of `load_device()`
should import from `cmsis_svd` directly (see loader.py).
"""

from __future__ import annotations

import json
from enum import Enum

from pydantic import BaseModel, ConfigDict


class AccessType(str, Enum):
    """Mirrors the CMSIS-SVD `access` enumeration, plus UNKNOWN.

    UNKNOWN is used only when access could not be determined anywhere in the
    SVD inheritance chain (register/field) — never guessed.
    """

    READ_ONLY = "read-only"
    WRITE_ONLY = "write-only"
    READ_WRITE = "read-write"
    WRITE_ONCE = "writeOnce"
    READ_WRITE_ONCE = "read-writeOnce"
    UNKNOWN = "unknown"


class _Frozen(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")


class EnumeratedValue(_Frozen):
    name: str
    value: int
    description: str | None = None
    is_default: bool = False
    source_ref: str


class Field(_Frozen):
    name: str
    description: str | None = None
    bit_offset: int
    bit_width: int
    access: AccessType
    enumerated_values: tuple[EnumeratedValue, ...] = ()
    source_ref: str


class Register(_Frozen):
    name: str
    description: str | None = None
    address_offset: int
    size: int
    access: AccessType
    reset_value: int
    reset_mask: int
    fields: tuple[Field, ...] = ()
    source_ref: str


class Peripheral(_Frozen):
    name: str
    description: str | None = None
    base_address: int
    registers: tuple[Register, ...] = ()
    source_ref: str


class Device(_Frozen):
    name: str
    description: str | None = None
    vendor: str | None = None
    series: str | None = None
    peripherals: tuple[Peripheral, ...] = ()
    source_ref: str

    def canonical_json(self) -> str:
        """Deterministic, byte-identical-for-identical-input JSON.

        Sorted keys, no whitespace variance, no timestamps.
        """
        data = self.model_dump(mode="json")
        return json.dumps(data, sort_keys=True, separators=(",", ":"))
