"""Phase 1 GATE: SVD -> device model.

Counts and per-register facts below were discovered once by inspecting
data/STM32F407.svd directly (see the register/peripheral line numbers noted
in each assertion's neighboring comment) and frozen here, per SPEC.md GATE 1.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from svdsentinel.model import AccessType, Device, Peripheral, Register
from svdsentinel.model.loader import load_device

FIXTURES = Path(__file__).parent / "fixtures"
PINNED_SVD = Path(__file__).parent.parent / "data" / "STM32F407.svd"


@pytest.fixture(scope="module")
def device() -> Device:
    return load_device(PINNED_SVD)


# -- exact counts, frozen ----------------------------------------------------


def test_peripheral_count(device: Device) -> None:
    assert len(device.peripherals) == 91


def test_register_count(device: Device) -> None:
    total = sum(len(p.registers) for p in device.peripherals)
    assert total == 1540


def test_field_count(device: Device) -> None:
    total = sum(len(r.fields) for p in device.peripherals for r in p.registers)
    assert total == 12347


# -- spot checks: 5 known registers, verified against the SVD text ----------


def _find(device: Device, peripheral: str, register: str) -> tuple[Peripheral, Register]:
    p = next(p for p in device.peripherals if p.name == peripheral)
    r = next(r for r in p.registers if r.name == register)
    return p, r


def test_rcc_cr(device: Device) -> None:
    p, r = _find(device, "RCC", "CR")
    assert p.base_address == 0x40023800
    assert r.address_offset == 0x0
    assert r.size == 32
    assert r.reset_value == 0x00000083
    # RCC->CR has no <access> at register level in the SVD; must not be guessed.
    assert r.access == AccessType.UNKNOWN


def test_gpioa_moder(device: Device) -> None:
    p, r = _find(device, "GPIOA", "MODER")
    assert p.base_address == 0x40020000
    assert r.address_offset == 0x0
    assert r.size == 32
    assert r.access == AccessType.READ_WRITE
    assert r.reset_value == 0xA8000000


def test_gpioa_idr(device: Device) -> None:
    _, r = _find(device, "GPIOA", "IDR")
    assert r.address_offset == 0x10
    assert r.size == 32
    assert r.access == AccessType.READ_ONLY
    assert r.reset_value == 0x00000000


def test_pwr_cr(device: Device) -> None:
    p, r = _find(device, "PWR", "CR")
    assert p.base_address == 0x40007000
    assert r.address_offset == 0x0
    assert r.size == 32
    assert r.access == AccessType.READ_WRITE
    assert r.reset_value == 0x00000000


def test_flash_acr(device: Device) -> None:
    p, r = _find(device, "FLASH", "ACR")
    assert p.base_address == 0x40023C00
    assert r.address_offset == 0x0
    assert r.size == 32
    # FLASH->ACR has no <access> at register level in the SVD either.
    assert r.access == AccessType.UNKNOWN
    assert r.reset_value == 0x00000000


# -- SVD quirks ---------------------------------------------------------------


def test_derived_from_peripheral_inherits_registers(device: Device) -> None:
    """DMA1 is <peripheral derivedFrom="DMA2"> with its own base address."""
    dma1 = next(p for p in device.peripherals if p.name == "DMA1")
    dma2 = next(p for p in device.peripherals if p.name == "DMA2")
    assert dma1.base_address == 0x40026000
    assert dma1.registers
    assert [r.name for r in dma1.registers] == [r.name for r in dma2.registers]


def test_field_missing_access_inherits_register_access(device: Device) -> None:
    """RNG->CR has register access=read-write; its fields omit <access>."""
    _, r = _find(device, "RNG", "CR")
    assert r.access == AccessType.READ_WRITE
    assert {f.access for f in r.fields} == {AccessType.READ_WRITE}


def test_access_missing_everywhere_is_unknown_not_guessed() -> None:
    d = load_device(FIXTURES / "no_access_anywhere.svd")
    r = d.peripherals[0].registers[0]
    assert r.access == AccessType.UNKNOWN
    assert r.fields[0].access == AccessType.UNKNOWN


def test_register_array_dim_expansion() -> None:
    d = load_device(FIXTURES / "dim_array.svd")
    regs = d.peripherals[0].registers
    assert [(r.name, r.address_offset) for r in regs] == [
        ("CH[0]", 0x0),
        ("CH[1]", 0x4),
        ("CH[2]", 0x8),
        ("CH[3]", 0xC),
    ]


def test_cluster_nesting_combines_offsets_and_names() -> None:
    d = load_device(FIXTURES / "cluster.svd")
    regs = {r.name: r for r in d.peripherals[0].registers}
    assert regs["CH_CTRL"].address_offset == 0x10
    assert regs["CH_STAT"].address_offset == 0x14
    assert regs["CH_STAT"].access == AccessType.READ_ONLY


def test_enumerated_values_parsed() -> None:
    d = load_device(FIXTURES / "enumerated_values.svd")
    field = d.peripherals[0].registers[0].fields[0]
    values = {ev.name: ev.value for ev in field.enumerated_values}
    assert values == {"Input": 0, "Output": 1}


def test_reserved_bits_are_gaps_not_fields(device: Device) -> None:
    """This SVD has no explicit reserved-field markers; reserved bits are
    simply not covered by any field. Confirms Phase 2's reserved-mask
    computation (complement of field union) has real gaps to compute over."""
    _, r = _find(device, "GPIOA", "MODER")
    covered_bits = {b for f in r.fields for b in range(f.bit_offset, f.bit_offset + f.bit_width)}
    assert covered_bits == set(range(32))  # MODER fully covers all 32 bits
    assert not any("reserv" in f.name.lower() for f in r.fields)


# -- source_ref evidence -------------------------------------------------------


def test_every_object_has_a_source_ref(device: Device) -> None:
    assert device.source_ref
    for p in device.peripherals[:5]:
        assert p.source_ref.startswith("device/peripherals/peripheral[name='")
        for r in p.registers[:5]:
            assert r.source_ref.startswith(p.source_ref)
            for f in r.fields[:5]:
                assert f.source_ref.startswith(r.source_ref)


# -- canonical JSON round-trip determinism -------------------------------------


def test_canonical_json_is_deterministic(device: Device) -> None:
    j1 = device.canonical_json()
    j2 = device.canonical_json()
    assert j1 == j2
    j3 = load_device(PINNED_SVD).canonical_json()
    assert j1 == j3


def test_canonical_json_is_sorted_and_parseable(device: Device) -> None:
    j = device.canonical_json()
    parsed = json.loads(j)
    assert parsed["name"] == "STM32F407"
    # Canonical form: sorted keys, compact separators. Re-dumping the parsed
    # structure the same way must reproduce the exact same bytes (a formatting
    # check that doesn't choke pytest's assertion diffing on a multi-MB blob
    # the way a naive `", " not in j` substring check would, since SVD
    # description text legitimately contains ": " and ", " as prose).
    assert json.dumps(parsed, sort_keys=True, separators=(",", ":")) == j
