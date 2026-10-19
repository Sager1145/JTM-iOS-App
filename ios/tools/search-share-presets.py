#!/usr/bin/env python3
"""Exhaustively search ticket-module share-composer presets.

The search enumerates every card order and every allowed shape/scale choice,
then places cards with the same row-major first-fit rule as ShareLayout.pack.
"""

from __future__ import annotations

from dataclasses import dataclass


GRIDS = {
    "square": (6, 6),
    "landscape": (8, 6),
    "portrait": (6, 8),
    "wide": (12, 7),
    "tall": (6, 11),
}

BASE_SPANS = {
    "small": (2, 2),
    "medium": (3, 2),
    "tall": (2, 3),
    "large": (3, 3),
}

PRESETS = {
    "japanIslands": (
        "ticket", "hokkaido", "honshu", "shikoku", "kyushu", "okinawa"
    ),
    "taiwan": ("ticket", "taiwan"),
    "hongKong": ("ticket", "hongKong"),
    "macau": ("ticket", "macau"),
}

PREFERRED_SHAPES = {
    "hokkaido": frozenset(("small", "medium")),
    "honshu": frozenset(("medium", "large")),
    "shikoku": frozenset(("medium", "small")),
    "kyushu": frozenset(("small", "tall")),
    "okinawa": frozenset(("small", "tall")),
    "taiwan": frozenset(("tall",)),
    "hongKong": frozenset(("medium", "small")),
    "macau": frozenset(("tall", "small")),
}


@dataclass(frozen=True)
class Size:
    shape: str
    scale: int
    columns: int
    rows: int

    @property
    def area(self) -> int:
        return self.columns * self.rows

    @property
    def label(self) -> str:
        return f"{self.shape}:{self.scale}"


def allowed_sizes(card: str, columns: int, rows: int) -> tuple[Size, ...]:
    shapes = ("medium",) if card == "ticket" else tuple(BASE_SPANS)
    result = []
    for shape in shapes:
        base_columns, base_rows = BASE_SPANS[shape]
        for scale in range(1, 4):
            width, height = base_columns * scale, base_rows * scale
            if width <= columns and height <= rows:
                result.append(Size(shape, scale, width, height))
    # Larger choices first establish a strong pruning bound early.
    return tuple(sorted(result, key=lambda size: (-size.area, -size.scale, size.label)))


def placement_masks(size: Size, columns: int, rows: int) -> tuple[int, ...]:
    """Return row-major placements in the order ShareLayout.pack considers them."""
    result = []
    for row in range(rows - size.rows + 1):
        for column in range(columns - size.columns + 1):
            candidate = 0
            for y in range(row, row + size.rows):
                candidate |= ((1 << size.columns) - 1) << (y * columns + column)
            result.append(candidate)
    return tuple(result)


def first_fit(mask: int, placements: tuple[int, ...]) -> int | None:
    """Return the occupied mask after exact ShareLayout.pack first-fit placement."""
    for candidate in placements:
        if mask & candidate == 0:
            return mask | candidate
    return None


def score(cards: tuple[str, ...], sizes: tuple[Size, ...]) -> tuple[int, ...]:
    by_card = dict(zip(cards, sizes))
    covered = sum(size.area for size in sizes)
    ticket_scale = by_card["ticket"].scale
    geography_matches = sum(
        size.shape in PREFERRED_SHAPES.get(card, ())
        for card, size in by_card.items()
        if card != "ticket"
    )
    if "honshu" in by_card:
        other_areas = [
            size.area for card, size in by_card.items()
            if card not in ("ticket", "honshu")
        ]
        honshu_dominates = by_card["honshu"].area >= max(other_areas)
        honshu_area = by_card["honshu"].area
    else:
        honshu_dominates = True
        honshu_area = 0
    return (
        covered,
        ticket_scale,
        int(honshu_dominates),
        geography_matches,
        honshu_area,
    )


def search(preset: str, ratio: str) -> tuple[tuple[int, ...], tuple[str, ...], tuple[Size, ...]]:
    columns, rows = GRIDS[ratio]
    cards = PRESETS[preset]
    options = {card: allowed_sizes(card, columns, rows) for card in cards}
    placements = {
        size: placement_masks(size, columns, rows)
        for choices in options.values() for size in choices
    }
    best: tuple | None = None
    best_order: tuple[str, ...] | None = None
    best_sizes: tuple[Size, ...] | None = None

    seen: set[tuple] = set()

    def visit(
        remaining: frozenset[str],
        mask: int,
        order: tuple[str, ...],
        chosen: tuple[Size, ...],
        ticket_scale: int,
        geography_matches: int,
        honshu_area: int,
        largest_other_island: int,
        covered: int,
    ) -> None:
        nonlocal best, best_order, best_sizes
        maximum_remaining = sum(options[card][0].area for card in remaining)
        if best is not None:
            maximum_matches = geography_matches + sum(
                card != "ticket" for card in remaining
            )
            maximum_ticket = ticket_scale or max(
                (size.scale for size in options["ticket"]), default=0
            )
            maximum_honshu = honshu_area or max(
                (size.area for size in options.get("honshu", ())), default=0
            )
            optimistic = (
                min(columns * rows, covered + maximum_remaining),
                maximum_ticket, 1, maximum_matches, maximum_honshu,
            )
            if optimistic < best:
                return
        state = (
            remaining, mask, ticket_scale, geography_matches,
            honshu_area, largest_other_island,
        )
        if state in seen:
            return
        seen.add(state)
        if not remaining:
            candidate = (
                covered,
                ticket_scale,
                int(honshu_area >= largest_other_island),
                geography_matches,
                honshu_area,
            )
            if best is None or candidate > best:
                best, best_order, best_sizes = candidate, order, chosen
            return
        for card in sorted(remaining):
            for size in options[card]:
                placed = first_fit(mask, placements[size])
                if placed is None:
                    continue
                visit(
                    remaining - {card},
                    placed,
                    order + (card,),
                    chosen + (size,),
                    size.scale if card == "ticket" else ticket_scale,
                    geography_matches
                    + int(size.shape in PREFERRED_SHAPES.get(card, ())),
                    size.area if card == "honshu" else honshu_area,
                    max(largest_other_island, size.area)
                    if card not in ("ticket", "honshu") else largest_other_island,
                    covered + size.area,
                )

    visit(frozenset(cards), 0, (), (), 0, 0, 0, 0, 0)

    assert best is not None and best_order is not None and best_sizes is not None
    return best, best_order, best_sizes


def main() -> None:
    for preset in PRESETS:
        print(preset)
        for ratio in GRIDS:
            result, order, sizes = search(preset, ratio)
            cards = ", ".join(
                f"{card}={size.label}" for card, size in zip(order, sizes)
            )
            print(f"  {ratio:9} covered={result[0]:2}  {cards}")


if __name__ == "__main__":
    main()
