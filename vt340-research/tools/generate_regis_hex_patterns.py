#!/usr/bin/env python3
"""Generate a compact ReGIS honeycomb pattern-fill conformance stream."""

from __future__ import annotations

import argparse
import math
from pathlib import Path


Point = tuple[float, float]


def polygon_area(points: list[Point]) -> float:
	return sum(
		x1 * y2 - x2 * y1
		for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1])
	) / 2.0


def clip_polygon(subject: list[Point], clipper: list[Point]) -> list[Point]:
	"""Sutherland-Hodgman intersection for two convex polygons."""
	if not subject:
		return []
	orientation = 1.0 if polygon_area(clipper) >= 0 else -1.0
	result = subject
	for edge_start, edge_end in zip(clipper, clipper[1:] + clipper[:1]):
		previous = result
		result = []
		if not previous:
			break

		def inside(point: Point) -> bool:
			cross = ((edge_end[0] - edge_start[0]) * (point[1] - edge_start[1]) -
				(edge_end[1] - edge_start[1]) * (point[0] - edge_start[0]))
			return orientation * cross >= -1.0e-7

		def intersection(first: Point, second: Point) -> Point:
			rx, ry = second[0] - first[0], second[1] - first[1]
			sx, sy = edge_end[0] - edge_start[0], edge_end[1] - edge_start[1]
			denominator = rx * sy - ry * sx
			if abs(denominator) < 1.0e-9:
				return second
			qx, qy = edge_start[0] - first[0], edge_start[1] - first[1]
			t = (qx * sy - qy * sx) / denominator
			return first[0] + t * rx, first[1] + t * ry

		prior = previous[-1]
		prior_inside = inside(prior)
		for current in previous:
			current_inside = inside(current)
			if current_inside != prior_inside:
				result.append(intersection(prior, current))
			if current_inside:
				result.append(current)
			prior = current
			prior_inside = current_inside
	return result


def clip_segment(first: Point, second: Point, polygon: list[Point]) -> tuple[Point, Point] | None:
	"""Clip a segment to a convex polygon using half-plane intervals."""
	orientation = 1.0 if polygon_area(polygon) >= 0 else -1.0
	t_min, t_max = 0.0, 1.0
	dx, dy = second[0] - first[0], second[1] - first[1]
	for edge_start, edge_end in zip(polygon, polygon[1:] + polygon[:1]):
		ex, ey = edge_end[0] - edge_start[0], edge_end[1] - edge_start[1]
		base = orientation * (ex * (first[1] - edge_start[1]) - ey * (first[0] - edge_start[0]))
		slope = orientation * (ex * dy - ey * dx)
		if abs(slope) < 1.0e-9:
			if base < 0:
				return None
			continue
		boundary = -base / slope
		if slope > 0:
			t_min = max(t_min, boundary)
		else:
			t_max = min(t_max, boundary)
		if t_min > t_max:
			return None
	return ((first[0] + t_min * dx, first[1] + t_min * dy),
		(first[0] + t_max * dx, first[1] + t_max * dy))


def integer_point(point: Point) -> tuple[int, int]:
	return round(point[0]), round(point[1])


def regis_polygon(points: list[Point]) -> str:
	cleaned: list[tuple[int, int]] = []
	for point in points:
		integer = integer_point(point)
		if not cleaned or integer != cleaned[-1]:
			cleaned.append(integer)
	if len(cleaned) > 1 and cleaned[0] == cleaned[-1]:
		cleaned.pop()
	if len(cleaned) < 3:
		return ""
	first = cleaned[0]
	vertices = "".join(f"[{x},{y}]" for x, y in cleaned[1:] + [first])
	return f"P[{first[0]},{first[1]}]F(V[]{vertices})"


def regis_line(first: Point, second: Point) -> str:
	x1, y1 = integer_point(first)
	x2, y2 = integer_point(second)
	if (x1, y1) == (x2, y2):
		return ""
	return f"P[{x1},{y1}]V[{x2},{y2}]"


def hexagon(cx: float, cy: float, radius: float, half_height: float) -> list[Point]:
	return [
		(cx - radius, cy),
		(cx - radius / 2, cy - half_height),
		(cx + radius / 2, cy - half_height),
		(cx + radius, cy),
		(cx + radius / 2, cy + half_height),
		(cx - radius / 2, cy + half_height),
	]


def line_family(polygon: list[Point], spacing: int, slope: int) -> list[str]:
	commands: list[str] = []
	xs = [point[0] for point in polygon]
	ys = [point[1] for point in polygon]
	if slope > 0:
		limits = (min(x - y for x, y in polygon), max(x - y for x, y in polygon))
	else:
		limits = (min(x + y for x, y in polygon), max(x + y for x, y in polygon))
	start = math.floor(limits[0] / spacing) * spacing
	for constant in range(start, math.ceil(limits[1] / spacing) * spacing + 1, spacing):
		margin = max(max(xs) - min(xs), max(ys) - min(ys)) + spacing
		if slope > 0:
			first = (min(xs) - margin, min(xs) - margin - constant)
			second = (max(xs) + margin, max(xs) + margin - constant)
		else:
			first = (min(xs) - margin, constant - (min(xs) - margin))
			second = (max(xs) + margin, constant - (max(xs) + margin))
		clipped = clip_segment(first, second, polygon)
		if clipped:
			command = regis_line(*clipped)
			if command:
				commands.append(command)
	return commands


def checkerboard(polygon: list[Point], cell: int = 12) -> list[str]:
	commands: list[str] = []
	min_x = math.floor(min(x for x, _ in polygon) / cell) * cell
	max_x = math.ceil(max(x for x, _ in polygon) / cell) * cell
	min_y = math.floor(min(y for _, y in polygon) / cell) * cell
	max_y = math.ceil(max(y for _, y in polygon) / cell) * cell
	for x in range(min_x, max_x, cell):
		for y in range(min_y, max_y, cell):
			if ((x // cell) + (y // cell)) & 1:
				clipped = clip_polygon(
					[(x, y), (x + cell, y), (x + cell, y + cell), (x, y + cell)], polygon)
				command = regis_polygon(clipped)
				if command:
					commands.append(command)
	return commands


def tiled_shapes(polygon: list[Point], spacing: int, shape: str) -> list[str]:
	commands: list[str] = []
	min_x = math.floor(min(x for x, _ in polygon) / spacing) * spacing
	max_x = math.ceil(max(x for x, _ in polygon) / spacing) * spacing
	min_y = math.floor(min(y for _, y in polygon) / spacing) * spacing
	max_y = math.ceil(max(y for _, y in polygon) / spacing) * spacing
	for x in range(min_x, max_x + 1, spacing):
		for y in range(min_y, max_y + 1, spacing):
			if shape == "dot":
				subject = [(x, y - 3), (x + 3, y), (x, y + 3), (x - 3, y)]
			else:
				subject = [(x, y - 6), (x + 6, y), (x, y + 6), (x - 6, y)]
			clipped = clip_polygon(subject, polygon)
			command = regis_polygon(clipped)
			if command:
				commands.append(command)
	return commands


def chevrons(polygon: list[Point], width: int = 16, height: int = 8) -> list[str]:
	commands: list[str] = []
	min_x = math.floor(min(x for x, _ in polygon) / width) * width - width
	max_x = math.ceil(max(x for x, _ in polygon) / width) * width + width
	min_y = math.floor(min(y for _, y in polygon) / (height * 2)) * height * 2
	max_y = math.ceil(max(y for _, y in polygon) / (height * 2)) * height * 2
	for baseline in range(min_y, max_y + 1, height * 2):
		points: list[Point] = []
		for x in range(min_x, max_x + width, width):
			points.append((x, baseline + (height if (x // width) & 1 else 0)))
		for first, second in zip(points, points[1:]):
			clipped = clip_segment(first, second, polygon)
			if clipped:
				command = regis_line(*clipped)
				if command:
					commands.append(command)
	return commands


def screen_hexagons() -> list[tuple[int, list[Point]]]:
	"""Cover the screen with one honeycomb and assign six pattern regions."""
	radius, half_height = 58.0, 50.0
	column_step, row_step = 87.0, 100.0
	screen = [(0, 0), (799, 0), (799, 479), (0, 479)]
	result: list[tuple[int, list[Point]]] = []
	for column in range(-1, 11):
		cx = column * column_step
		y_offset = half_height if column & 1 else 0.0
		for row in range(-1, 6):
			cy = row * row_step + y_offset
			clipped = clip_polygon(hexagon(cx, cy, radius, half_height), screen)
			if len(clipped) < 3 or abs(polygon_area(clipped)) < 1.0:
				continue
			region_x = min(2, max(0, int(cx // (800 / 3))))
			region_y = 0 if cy < 240 else 1
			result.append((region_y * 3 + region_x, clipped))
	return result


def generate() -> bytes:
	panels = [
		(5, "stripes"),
		(6, "checker"),
		(3, "dots"),
		(4, "crosshatch"),
		(1, "chevrons"),
		(5, "motif"),
	]
	commands = ["\x1bP1p", "W(F15)", "S(EA[0,0][799,479])"]
	all_hexagons = screen_hexagons()
	for panel_number, (color, pattern) in enumerate(panels):
		hexagons = [polygon for region, polygon in all_hexagons if region == panel_number]
		commands.append(f"W(I{color})")
		commands.extend(regis_polygon(polygon) for polygon in hexagons)
		commands.append("W(I0)")
		for polygon in hexagons:
			if pattern == "stripes":
				commands.extend(line_family(polygon, 10, -1))
			elif pattern == "checker":
				commands.extend(checkerboard(polygon))
			elif pattern == "dots":
				commands.extend(tiled_shapes(polygon, 14, "dot"))
			elif pattern == "crosshatch":
				commands.extend(line_family(polygon, 12, -1))
				commands.extend(line_family(polygon, 12, 1))
			elif pattern == "chevrons":
				commands.extend(chevrons(polygon))
			else:
				commands.extend(tiled_shapes(polygon, 18, "motif"))
		commands.append("W(I7)")
		for polygon in hexagons:
			outline = polygon + [polygon[0]]
			first = integer_point(outline[0])
			commands.append(f"P[{first[0]},{first[1]}]" +
				"V" + "".join(f"[{x},{y}]" for x, y in map(integer_point, outline[1:])))
	commands.extend(["P[0,0]", "\x1b\\"])
	return "".join(command for command in commands if command).encode("ascii")


def generate_linear_patterns() -> bytes:
	"""Generate a smaller scene whose strokes use ReGIS linear patterns."""
	panels = [
		(5, "10", 1, "diagonal"),
		(6, "10", 3, "cross"),
		(3, "11110000", 1, "diagonal"),
		(4, "11100100", 2, "cross"),
		(1, "10101010", 2, "chevrons"),
		(5, "11101010", 2, "reverse"),
	]
	commands = ["\x1bP1p", "W(F15)", "S(EA[0,0][799,479])"]
	all_hexagons = screen_hexagons()
	for panel_number, (color, pattern, multiplier, layout) in enumerate(panels):
		hexagons = [polygon for region, polygon in all_hexagons if region == panel_number]
		commands.extend([f"W(I{color})", f"W(P{pattern}(M{multiplier}))"])
		for polygon in hexagons:
			if layout == "diagonal":
				commands.extend(line_family(polygon, 9, -1))
			elif layout == "reverse":
				commands.extend(line_family(polygon, 9, 1))
			elif layout == "cross":
				commands.extend(line_family(polygon, 13, -1))
				commands.extend(line_family(polygon, 13, 1))
			else:
				commands.extend(chevrons(polygon, width=18, height=8))
	commands.extend(["W(I7)", "W(P1(M1))"])
	for _, polygon in all_hexagons:
		outline = polygon + [polygon[0]]
		first = integer_point(outline[0])
		commands.append(f"P[{first[0]},{first[1]}]" +
			"V" + "".join(f"[{x},{y}]" for x, y in map(integer_point, outline[1:])))
	commands.extend(["W(P1(M2))", "P[0,0]", "\x1b\\"])
	return "".join(command for command in commands if command).encode("ascii")


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--linear-patterns", action="store_true",
		help="generate a focused ReGIS W(P...M...) linear-pattern scene")
	parser.add_argument("output", type=Path)
	args = parser.parse_args()
	args.output.write_bytes(generate_linear_patterns() if args.linear_patterns else generate())


if __name__ == "__main__":
	main()
