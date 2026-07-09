"""SVD -> normalized Device model.

Uses the `cmsis_svd` package to parse and resolve SVD-specific quirks
(`derivedFrom`, `dim`/`dimIncrement` register and field arrays, cluster
nesting), then converts the result into our own pydantic model. No
`cmsis_svd` object is ever returned or passed downstream — see model/__init__.py.

`cmsis_svd` already performs, per the CMSIS-SVD schema:
- derivedFrom resolution for peripherals and registers (inherited registers/
  fields are copied onto the deriving element).
- register/field array (`dim`) expansion into individually named leaves
  (e.g. `DEVICEID[0]`, `DEVICEID[1]`), reachable via `.registers`/`.fields`
  on the `SVDRegisterArray`/`SVDFieldArray` wrapper.
- cluster nesting: `SVDRegisterCluster`/`SVDRegisterClusterArray` wrappers
  expose already-offset-combined, already-prefixed-named leaf registers via
  `.registers` (e.g. cluster `CH` + register `CTRL` -> `CH_CTRL` at the
  combined address offset).
- field access inheritance from the owning register when a field omits its
  own `<access>`.

We do not re-guess or override any of that; we only map its output onto our
model, and use AccessType.UNKNOWN (never a default) when access is missing
from the whole chain.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from cmsis_svd.model import SVDAccessType, SVDDevice
from cmsis_svd.parser import SVDParser

from svdsentinel.model import AccessType, Device, EnumeratedValue, Field, Peripheral, Register

_ACCESS_MAP: dict[SVDAccessType, AccessType] = {
    SVDAccessType.READ_ONLY: AccessType.READ_ONLY,
    SVDAccessType.WRITE_ONLY: AccessType.WRITE_ONLY,
    SVDAccessType.READ_WRITE: AccessType.READ_WRITE,
    SVDAccessType.WRITE_ONCE: AccessType.WRITE_ONCE,
    SVDAccessType.READ_WRITE_ONCE: AccessType.READ_WRITE_ONCE,
}


def _map_access(raw: SVDAccessType | None) -> AccessType:
    if raw is None:
        return AccessType.UNKNOWN
    return _ACCESS_MAP[raw]


def _flatten(items: Any, wrapper_attrs: tuple[str, ...]) -> list[Any]:
    """Recursively expand array/cluster wrapper nodes into leaf SVD objects.

    `cmsis_svd` represents `dim` arrays and `<cluster>` nesting as wrapper
    types (`SVDRegisterArray`, `SVDFieldArray`, `SVDRegisterCluster`,
    `SVDRegisterClusterArray`, ...) that expose their already-offset-combined,
    already-named children through one of a few attribute names depending on
    wrapper kind. A node is a wrapper iff it exposes any of `wrapper_attrs`;
    leaf nodes (SVDRegister/SVDField) expose none of them.
    """
    out: list[Any] = []
    for item in items:
        nested = next(
            (getattr(item, attr) for attr in wrapper_attrs if getattr(item, attr, None) is not None),
            None,
        )
        if nested is not None:
            out.extend(_flatten(nested, wrapper_attrs))
        else:
            out.append(item)
    return out


_REGISTER_WRAPPER_ATTRS = ("registers", "clusters")
_FIELD_WRAPPER_ATTRS = ("fields",)
_PERIPHERAL_WRAPPER_ATTRS = ("peripherals",)


def _convert_enumerated_values(svd_field: Any, field_ref: str) -> tuple[EnumeratedValue, ...]:
    groups = getattr(svd_field, "enumerated_values", None) or ()
    result: list[EnumeratedValue] = []
    for group in groups:
        for ev in group.enumerated_values:
            if ev.value is None:
                # `<enumeratedValue>` with `<isDefault>` and no numeric value
                # covers the "any other value" case; we have nothing to
                # assert about a specific value, so skip it rather than guess.
                continue
            result.append(
                EnumeratedValue(
                    name=ev.name,
                    value=ev.value,
                    description=ev.description,
                    is_default=bool(ev.is_default),
                    source_ref=f"{field_ref}/enumeratedValues/enumeratedValue[name='{ev.name}']",
                )
            )
    return tuple(result)


def _convert_field(svd_field: Any, register_ref: str) -> Field:
    ref = f"{register_ref}/fields/field[name='{svd_field.name}']"
    return Field(
        name=svd_field.name,
        description=svd_field.description,
        bit_offset=svd_field.bit_offset,
        bit_width=svd_field.bit_width,
        access=_map_access(svd_field.access),
        enumerated_values=_convert_enumerated_values(svd_field, ref),
        source_ref=ref,
    )


def _convert_register(svd_register: Any, peripheral_ref: str) -> Register:
    ref = f"{peripheral_ref}/registers/register[name='{svd_register.name}']"
    fields = _flatten(svd_register.fields, _FIELD_WRAPPER_ATTRS)
    return Register(
        name=svd_register.name,
        description=svd_register.description,
        address_offset=svd_register.address_offset,
        size=svd_register.size,
        access=_map_access(svd_register.access),
        reset_value=svd_register.reset_value or 0,
        reset_mask=svd_register.reset_mask if svd_register.reset_mask is not None else 0xFFFFFFFF,
        fields=tuple(_convert_field(f, ref) for f in fields),
        source_ref=ref,
    )


def _convert_peripheral(svd_peripheral: Any, device_ref: str) -> Peripheral:
    ref = f"{device_ref}/peripherals/peripheral[name='{svd_peripheral.name}']"
    registers = _flatten(svd_peripheral.registers, _REGISTER_WRAPPER_ATTRS)
    return Peripheral(
        name=svd_peripheral.name,
        description=svd_peripheral.description,
        base_address=svd_peripheral.base_address,
        registers=tuple(_convert_register(r, ref) for r in registers),
        source_ref=ref,
    )


def _convert_device(svd_device: SVDDevice, svd_path: Path) -> Device:
    ref = "device"
    if svd_device.name is None:
        raise ValueError(f"{svd_path}: <device> is missing the mandatory <name> element")
    peripherals = _flatten(svd_device.peripherals, _PERIPHERAL_WRAPPER_ATTRS)
    return Device(
        name=svd_device.name,
        description=svd_device.description,
        vendor=svd_device.vendor,
        series=svd_device.series,
        peripherals=tuple(_convert_peripheral(p, ref) for p in peripherals),
        source_ref=f"{ref}[file='{svd_path.name}']",
    )


def load_device(svd_path: str | Path) -> Device:
    """Parse an SVD file into a normalized, vendor-independent Device model."""
    path = Path(svd_path)
    parser = SVDParser.for_xml_file(str(path))
    svd_device = parser.get_device()
    return _convert_device(svd_device, path)
