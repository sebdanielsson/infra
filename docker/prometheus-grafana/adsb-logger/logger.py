#!/usr/bin/env python3
"""Flight logger for the flightradar ADS-B receiver.

Polls readsb's aircraft.json (served by ultrafeeder/tar1090 on the Pi) and
records one row per *sighting* — a continuous stretch of contact with one
aircraft — plus a downsampled position track, into a SQLite database that
Grafana reads directly.

Prometheus answers "how is the receiver doing"; this answers "what flew over,
when, and where". Deliberately stdlib-only so the container is a stock
python:*-alpine with no build step and no pip install at runtime.
"""

from __future__ import annotations

import csv
import gzip
import io
import json
import logging
import math
import os
import signal
import sqlite3
import time
import urllib.error
import urllib.request

LOG = logging.getLogger("adsb-logger")

JSON_URL = os.environ.get(
    "ADSB_JSON_URL", "http://flightradar.risk-bee.ts.net:8504/data/aircraft.json"
)
DB_PATH = os.environ.get("ADSB_DB_PATH", "/data/adsb.db")


def _env_coord(name: str) -> float | None:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


RECEIVER_LAT = _env_coord("ADSB_LAT")
RECEIVER_LON = _env_coord("ADSB_LON")
# Both or neither. Half a position is worse than none: pairing one real
# coordinate with a zero default yields distances that look plausible and are
# wrong by hundreds of kilometres.
RECEIVER_SET = RECEIVER_LAT is not None and RECEIVER_LON is not None

POLL_INTERVAL = float(os.environ.get("ADSB_POLL_INTERVAL", "5"))
# One stored track point per aircraft per this many seconds. At ~40 aircraft
# in view this is roughly 115k rows/day.
POSITION_INTERVAL = float(os.environ.get("ADSB_POSITION_INTERVAL", "30"))
# Losing contact for longer than this ends the sighting; the next contact
# starts a new one.
SESSION_GAP = float(os.environ.get("ADSB_SESSION_GAP", "300"))
FLUSH_INTERVAL = float(os.environ.get("ADSB_FLUSH_INTERVAL", "30"))
POSITION_RETENTION_DAYS = int(os.environ.get("ADSB_POSITION_RETENTION_DAYS", "30"))
SIGHTING_RETENTION_DAYS = int(os.environ.get("ADSB_SIGHTING_RETENTION_DAYS", "730"))

AIRLINE_URL = os.environ.get(
    "ADSB_AIRLINE_URL",
    "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airlines.dat",
)
AIRLINE_REFRESH_DAYS = int(os.environ.get("ADSB_AIRLINE_REFRESH_DAYS", "30"))

NM_TO_KM = 1.852
USER_AGENT = "adsb-logger/1.0 (+https://github.com/sebdanielsson/infra)"

SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
-- Set before any table exists so pruned pages can be returned to the
-- filesystem incrementally, without ever taking a full VACUUM lock.
PRAGMA auto_vacuum = INCREMENTAL;

CREATE TABLE IF NOT EXISTS sighting (
    id             INTEGER PRIMARY KEY,
    hex            TEXT    NOT NULL,
    first_seen     INTEGER NOT NULL,
    last_seen      INTEGER NOT NULL,
    duration_s     INTEGER NOT NULL DEFAULT 0,
    callsign       TEXT,
    airline_code   TEXT,
    airline        TEXT,
    registration   TEXT,
    icao_type      TEXT,
    aircraft_desc  TEXT,
    country        TEXT,
    military       INTEGER NOT NULL DEFAULT 0,
    squawk         TEXT,
    emergency      TEXT,
    category       TEXT,
    messages       INTEGER NOT NULL DEFAULT 0,
    positions      INTEGER NOT NULL DEFAULT 0,
    alt_min        INTEGER,
    alt_max        INTEGER,
    gs_max         REAL,
    rssi_max       REAL,
    dist_min_km    REAL,
    dist_max_km    REAL,
    bearing_closest REAL,
    lat_closest    REAL,
    lon_closest    REAL
);
CREATE INDEX IF NOT EXISTS sighting_first_seen  ON sighting (first_seen);
CREATE INDEX IF NOT EXISTS sighting_last_seen   ON sighting (last_seen);
CREATE INDEX IF NOT EXISTS sighting_hex         ON sighting (hex);
CREATE INDEX IF NOT EXISTS sighting_reg         ON sighting (registration);
CREATE INDEX IF NOT EXISTS sighting_airline     ON sighting (airline_code);
CREATE INDEX IF NOT EXISTS sighting_type        ON sighting (icao_type);

CREATE TABLE IF NOT EXISTS position (
    ts          INTEGER NOT NULL,
    sighting_id INTEGER NOT NULL,
    hex         TEXT    NOT NULL,
    lat         REAL,
    lon         REAL,
    alt         INTEGER,
    gs          REAL,
    track       REAL,
    dist_km     REAL,
    bearing     REAL,
    rssi        REAL
);
CREATE INDEX IF NOT EXISTS position_ts  ON position (ts);
CREATE INDEX IF NOT EXISTS position_sid ON position (sighting_id);

CREATE TABLE IF NOT EXISTS airline (
    code    TEXT PRIMARY KEY,
    name    TEXT,
    country TEXT
);

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
"""

# ICAO 24-bit address allocations (Annex 10 Vol III, Chapter 9 appendix), taken
# verbatim from tar1090's flags.js so the country attribution here matches what
# the map shows. Kept in source order: the table is ordered specific-first, and
# the lookup returns the first hit.
ICAO_RANGES: list[tuple[int, int, str]] = [
    (0x004000, 0x0047FF, "Zimbabwe"),
    (0x006000, 0x006FFF, "Mozambique"),
    (0x008000, 0x00FFFF, "South Africa"),
    (0x010000, 0x017FFF, "Egypt"),
    (0x018000, 0x01FFFF, "Libya"),
    (0x020000, 0x027FFF, "Morocco"),
    (0x028000, 0x02FFFF, "Tunisia"),
    (0x030000, 0x0307FF, "Botswana"),
    (0x032000, 0x032FFF, "Burundi"),
    (0x034000, 0x034FFF, "Cameroon"),
    (0x035000, 0x0357FF, "Comoros"),
    (0x036000, 0x036FFF, "Republic of the Congo"),
    (0x038000, 0x038FFF, "Côte d’Ivoire"),
    (0x03E000, 0x03EFFF, "Gabon"),
    (0x040000, 0x040FFF, "Ethiopia"),
    (0x042000, 0x042FFF, "Equatorial Guinea"),
    (0x044000, 0x044FFF, "Ghana"),
    (0x046000, 0x046FFF, "Guinea"),
    (0x048000, 0x0487FF, "Guinea-Bissau"),
    (0x04A000, 0x04A7FF, "Lesotho"),
    (0x04C000, 0x04CFFF, "Kenya"),
    (0x050000, 0x050FFF, "Liberia"),
    (0x054000, 0x054FFF, "Madagascar"),
    (0x058000, 0x058FFF, "Malawi"),
    (0x05A000, 0x05A7FF, "Maldives"),
    (0x05C000, 0x05CFFF, "Mali"),
    (0x05E000, 0x05E7FF, "Mauritania"),
    (0x060000, 0x0607FF, "Mauritius"),
    (0x062000, 0x062FFF, "Niger"),
    (0x064000, 0x064FFF, "Nigeria"),
    (0x068000, 0x068FFF, "Uganda"),
    (0x06A000, 0x06AFFF, "Qatar"),
    (0x06C000, 0x06CFFF, "Central African Republic"),
    (0x06E000, 0x06EFFF, "Rwanda"),
    (0x070000, 0x070FFF, "Senegal"),
    (0x074000, 0x0747FF, "Seychelles"),
    (0x076000, 0x0767FF, "Sierra Leone"),
    (0x078000, 0x078FFF, "Somalia"),
    (0x07A000, 0x07A7FF, "Eswatini"),
    (0x07C000, 0x07CFFF, "Sudan"),
    (0x080000, 0x080FFF, "Tanzania"),
    (0x084000, 0x084FFF, "Chad"),
    (0x088000, 0x088FFF, "Togo"),
    (0x08A000, 0x08AFFF, "Zambia"),
    (0x08C000, 0x08CFFF, "DR Congo"),
    (0x090000, 0x090FFF, "Angola"),
    (0x094000, 0x0947FF, "Benin"),
    (0x096000, 0x0967FF, "Cabo Verde"),
    (0x098000, 0x0987FF, "Djibouti"),
    (0x09A000, 0x09AFFF, "Gambia"),
    (0x09C000, 0x09CFFF, "Burkina Faso"),
    (0x09E000, 0x09E7FF, "São Tomé and Príncipe"),
    (0x0A0000, 0x0A7FFF, "Algeria"),
    (0x0A8000, 0x0A8FFF, "Bahamas"),
    (0x0AA000, 0x0AA7FF, "Barbados"),
    (0x0AB000, 0x0AB7FF, "Belize"),
    (0x0AC000, 0x0ADFFF, "Colombia"),
    (0x0AE000, 0x0AEFFF, "Costa Rica"),
    (0x0B0000, 0x0B0FFF, "Cuba"),
    (0x0B2000, 0x0B2FFF, "El Salvador"),
    (0x0B4000, 0x0B4FFF, "Guatemala"),
    (0x0B6000, 0x0B6FFF, "Guyana"),
    (0x0B8000, 0x0B8FFF, "Haiti"),
    (0x0BA000, 0x0BAFFF, "Honduras"),
    (0x0BC000, 0x0BC7FF, "Saint Vincent and the Grenadines"),
    (0x0BE000, 0x0BEFFF, "Jamaica"),
    (0x0C0000, 0x0C0FFF, "Nicaragua"),
    (0x0C2000, 0x0C2FFF, "Panama"),
    (0x0C4000, 0x0C4FFF, "Dominican Republic"),
    (0x0C6000, 0x0C6FFF, "Trinidad and Tobago"),
    (0x0C8000, 0x0C8FFF, "Suriname"),
    (0x0CA000, 0x0CA7FF, "Antigua and Barbuda"),
    (0x0CC000, 0x0CC7FF, "Grenada"),
    (0x0D0000, 0x0D7FFF, "Mexico"),
    (0x0D8000, 0x0DFFFF, "Venezuela"),
    (0x100000, 0x1FFFFF, "Russia"),
    (0x201000, 0x2017FF, "Namibia"),
    (0x202000, 0x2027FF, "Eritrea"),
    (0x300000, 0x33FFFF, "Italy"),
    (0x340000, 0x37FFFF, "Spain"),
    (0x380000, 0x3BFFFF, "France"),
    (0x3C0000, 0x3FFFFF, "Germany"),
    (0x400000, 0x4001BF, "Bermuda"),
    (0x4001C0, 0x4001FF, "Cayman Islands"),
    (0x400300, 0x4003FF, "Turks and Caicos Islands"),
    (0x424135, 0x4241F2, "Cayman Islands"),
    (0x424200, 0x4246FF, "Bermuda"),
    (0x424700, 0x424899, "Cayman Islands"),
    (0x424B00, 0x424BFF, "Isle of Man"),
    (0x43BE00, 0x43BEFF, "Bermuda"),
    (0x43E700, 0x43EAFD, "Isle of Man"),
    (0x43EAFE, 0x43EEFF, "Guernsey"),
    (0x400000, 0x43FFFF, "United Kingdom"),
    (0x440000, 0x447FFF, "Austria"),
    (0x448000, 0x44FFFF, "Belgium"),
    (0x450000, 0x457FFF, "Bulgaria"),
    (0x458000, 0x45FFFF, "Denmark"),
    (0x460000, 0x467FFF, "Finland"),
    (0x468000, 0x46FFFF, "Greece"),
    (0x470000, 0x477FFF, "Hungary"),
    (0x478000, 0x47FFFF, "Norway"),
    (0x480000, 0x487FFF, "Netherlands"),
    (0x488000, 0x48FFFF, "Poland"),
    (0x490000, 0x497FFF, "Portugal"),
    (0x498000, 0x49FFFF, "Czechia"),
    (0x4A0000, 0x4A7FFF, "Romania"),
    (0x4A8000, 0x4AFFFF, "Sweden"),
    (0x4B0000, 0x4B7FFF, "Switzerland"),
    (0x4B8000, 0x4BFFFF, "Turkey"),
    (0x4C0000, 0x4C7FFF, "Serbia"),
    (0x4C8000, 0x4C87FF, "Cyprus"),
    (0x4CA000, 0x4CAFFF, "Ireland"),
    (0x4CC000, 0x4CCFFF, "Iceland"),
    (0x4D0000, 0x4D07FF, "Luxembourg"),
    (0x4D2000, 0x4D27FF, "Malta"),
    (0x4D4000, 0x4D47FF, "Monaco"),
    (0x500000, 0x5007FF, "San Marino"),
    (0x501000, 0x5017FF, "Albania"),
    (0x501800, 0x501FFF, "Croatia"),
    (0x502800, 0x502FFF, "Latvia"),
    (0x503800, 0x503FFF, "Lithuania"),
    (0x504800, 0x504FFF, "Moldova"),
    (0x505800, 0x505FFF, "Slovakia"),
    (0x506800, 0x506FFF, "Slovenia"),
    (0x507800, 0x507FFF, "Uzbekistan"),
    (0x508000, 0x50FFFF, "Ukraine"),
    (0x510000, 0x5107FF, "Belarus"),
    (0x511000, 0x5117FF, "Estonia"),
    (0x512000, 0x5127FF, "North Macedonia"),
    (0x513000, 0x5137FF, "Bosnia and Herzegovina"),
    (0x514000, 0x5147FF, "Georgia"),
    (0x515000, 0x5157FF, "Tajikistan"),
    (0x516000, 0x5167FF, "Montenegro"),
    (0x600000, 0x6007FF, "Armenia"),
    (0x600800, 0x600FFF, "Azerbaijan"),
    (0x601000, 0x6017FF, "Kyrgyzstan"),
    (0x601800, 0x601FFF, "Turkmenistan"),
    (0x680000, 0x6807FF, "Bhutan"),
    (0x681000, 0x6817FF, "Micronesia, Federated States of"),
    (0x682000, 0x6827FF, "Mongolia"),
    (0x683000, 0x6837FF, "Kazakhstan"),
    (0x684000, 0x6847FF, "Palau"),
    (0x700000, 0x700FFF, "Afghanistan"),
    (0x702000, 0x702FFF, "Bangladesh"),
    (0x704000, 0x704FFF, "Myanmar"),
    (0x706000, 0x706FFF, "Kuwait"),
    (0x708000, 0x708FFF, "Laos"),
    (0x70A000, 0x70AFFF, "Nepal"),
    (0x70C000, 0x70C7FF, "Oman"),
    (0x70E000, 0x70EFFF, "Cambodia"),
    (0x710000, 0x717FFF, "Saudi Arabia"),
    (0x718000, 0x71FFFF, "South Korea"),
    (0x720000, 0x727FFF, "North Korea"),
    (0x728000, 0x72FFFF, "Iraq"),
    (0x730000, 0x737FFF, "Iran"),
    (0x738000, 0x73FFFF, "Israel"),
    (0x740000, 0x747FFF, "Jordan"),
    (0x748000, 0x74FFFF, "Lebanon"),
    (0x750000, 0x757FFF, "Malaysia"),
    (0x758000, 0x75FFFF, "Philippines"),
    (0x760000, 0x767FFF, "Pakistan"),
    (0x768000, 0x76FFFF, "Singapore"),
    (0x770000, 0x777FFF, "Sri Lanka"),
    (0x778000, 0x77FFFF, "Syria"),
    (0x789000, 0x789FFF, "Hong Kong"),
    (0x780000, 0x7BFFFF, "China"),
    (0x7C0000, 0x7FFFFF, "Australia"),
    (0x800000, 0x83FFFF, "India"),
    (0x840000, 0x87FFFF, "Japan"),
    (0x880000, 0x887FFF, "Thailand"),
    (0x888000, 0x88FFFF, "Viet Nam"),
    (0x890000, 0x890FFF, "Yemen"),
    (0x894000, 0x894FFF, "Bahrain"),
    (0x895000, 0x8957FF, "Brunei"),
    (0x896000, 0x896FFF, "United Arab Emirates"),
    (0x897000, 0x8977FF, "Solomon Islands"),
    (0x898000, 0x898FFF, "Papua New Guinea"),
    (0x899000, 0x8997FF, "Taiwan"),
    (0x8A0000, 0x8A7FFF, "Indonesia"),
    (0x900000, 0x9007FF, "Marshall Islands"),
    (0x901000, 0x9017FF, "Cook Islands"),
    (0x902000, 0x9027FF, "Samoa"),
    (0xA00000, 0xAFFFFF, "United States"),
    (0xC00000, 0xC3FFFF, "Canada"),
    (0xC80000, 0xC87FFF, "New Zealand"),
    (0xC88000, 0xC88FFF, "Fiji"),
    (0xC8A000, 0xC8A7FF, "Nauru"),
    (0xC8C000, 0xC8C7FF, "Saint Lucia"),
    (0xC8D000, 0xC8D7FF, "Tonga"),
    (0xC8E000, 0xC8E7FF, "Kiribati"),
    (0xC90000, 0xC907FF, "Vanuatu"),
    (0xC91000, 0xC917FF, "Andorra"),
    (0xC92000, 0xC927FF, "Dominica"),
    (0xC93000, 0xC937FF, "Saint Kitts and Nevis"),
    (0xC94000, 0xC947FF, "South Sudan"),
    (0xC95000, 0xC957FF, "Timor-Leste"),
    (0xC97000, 0xC977FF, "Tuvalu"),
    (0xE00000, 0xE3FFFF, "Argentina"),
    (0xE40000, 0xE7FFFF, "Brazil"),
    (0xE80000, 0xE80FFF, "Chile"),
    (0xE84000, 0xE84FFF, "Ecuador"),
    (0xE88000, 0xE88FFF, "Paraguay"),
    (0xE8C000, 0xE8CFFF, "Peru"),
    (0xE90000, 0xE90FFF, "Uruguay"),
    (0xE94000, 0xE94FFF, "Bolivia"),
    (0xF00000, 0xF07FFF, "ICAO (temporary)"),
    (0xF09000, 0xF097FF, "ICAO (special use)"),
]

EMERGENCY_SQUAWKS = {"7500": "hijack", "7600": "radio failure", "7700": "general"}


def country_for_hex(hex_code: str) -> str | None:
    try:
        addr = int(hex_code, 16)
    except ValueError:
        return None
    for lo, hi, name in ICAO_RANGES:
        if lo <= addr <= hi:
            return name
    return None


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0088
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


def fetch(url: str, timeout: float = 20.0) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
        data = resp.read()
    if resp.headers.get("Content-Encoding") == "gzip" or url.endswith(".gz"):
        data = gzip.decompress(data)
    return data


def as_int(value) -> int | None:
    """alt_baro is the integer altitude in feet, or the string "ground"."""
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str) and value.strip().lstrip("-").isdigit():
        return int(value)
    return None


def as_float(value) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


class Session:
    """Aggregates one continuous contact with one aircraft."""

    __slots__ = (
        "row_id", "hex", "first_seen", "last_seen", "callsign", "airline_code",
        "registration", "icao_type", "aircraft_desc", "country", "military",
        "squawk", "emergency", "category", "messages", "positions", "alt_min",
        "alt_max", "gs_max", "rssi_max", "dist_min_km", "dist_max_km",
        "bearing_closest", "lat_closest", "lon_closest", "last_position_ts",
        "dirty",
    )

    def __init__(self, hex_code: str, now: int, row_id: int | None = None):
        self.row_id = row_id
        self.hex = hex_code
        self.first_seen = now
        self.last_seen = now
        self.callsign = None
        self.airline_code = None
        self.registration = None
        self.icao_type = None
        self.aircraft_desc = None
        self.country = country_for_hex(hex_code)
        self.military = 0
        self.squawk = None
        self.emergency = None
        self.category = None
        self.messages = 0
        self.positions = 0
        self.alt_min = None
        self.alt_max = None
        self.gs_max = None
        self.rssi_max = None
        self.dist_min_km = None
        self.dist_max_km = None
        self.bearing_closest = None
        self.lat_closest = None
        self.lon_closest = None
        self.last_position_ts = 0.0
        self.dirty = True

    def update(self, ac: dict, now: int) -> tuple | None:
        """Fold one aircraft.json entry in. Returns a position row, or None."""
        self.last_seen = now
        self.dirty = True

        flight = (ac.get("flight") or "").strip()
        if flight:
            self.callsign = flight
            # An ICAO callsign is a 3-letter airline designator followed by a
            # flight number; anything else (a bare registration on a private
            # flight, for instance) has no airline to resolve.
            prefix = flight[:3]
            if len(flight) > 3 and prefix.isalpha() and any(c.isdigit() for c in flight[3:]):
                self.airline_code = prefix.upper()

        for attr, key in (
            ("registration", "r"),
            ("icao_type", "t"),
            ("aircraft_desc", "desc"),
            ("category", "category"),
        ):
            value = ac.get(key)
            if isinstance(value, str) and value.strip():
                setattr(self, attr, value.strip())

        squawk = ac.get("squawk")
        if isinstance(squawk, str) and squawk:
            self.squawk = squawk
            if squawk in EMERGENCY_SQUAWKS:
                self.emergency = EMERGENCY_SQUAWKS[squawk]
        emergency = ac.get("emergency")
        if isinstance(emergency, str) and emergency not in ("", "none"):
            self.emergency = emergency

        # dbFlags bit 0 marks military aircraft in the tar1090 database.
        db_flags = ac.get("dbFlags")
        if isinstance(db_flags, int) and db_flags & 1:
            self.military = 1

        messages = as_int(ac.get("messages"))
        if messages is not None and messages > self.messages:
            self.messages = messages

        alt = as_int(ac.get("alt_baro"))
        if alt is not None:
            self.alt_min = alt if self.alt_min is None else min(self.alt_min, alt)
            self.alt_max = alt if self.alt_max is None else max(self.alt_max, alt)

        gs = as_float(ac.get("gs"))
        if gs is not None and (self.gs_max is None or gs > self.gs_max):
            self.gs_max = gs

        rssi = as_float(ac.get("rssi"))
        if rssi is not None and (self.rssi_max is None or rssi > self.rssi_max):
            self.rssi_max = rssi

        lat, lon = as_float(ac.get("lat")), as_float(ac.get("lon"))
        if lat is None or lon is None:
            return None

        # readsb publishes r_dst/r_dir (nautical miles, degrees) whenever the
        # receiver position is configured; fall back to computing them.
        dist_nm = as_float(ac.get("r_dst"))
        if dist_nm is not None:
            dist_km = dist_nm * NM_TO_KM
        elif RECEIVER_SET:
            dist_km = haversine_km(RECEIVER_LAT, RECEIVER_LON, lat, lon)
        else:
            dist_km = None
        bearing = as_float(ac.get("r_dir"))
        if bearing is None and RECEIVER_SET:
            bearing = bearing_deg(RECEIVER_LAT, RECEIVER_LON, lat, lon)

        if dist_km is not None:
            if self.dist_max_km is None or dist_km > self.dist_max_km:
                self.dist_max_km = dist_km
            if self.dist_min_km is None or dist_km < self.dist_min_km:
                self.dist_min_km = dist_km
                self.bearing_closest = bearing
                self.lat_closest = lat
                self.lon_closest = lon

        if now - self.last_position_ts < POSITION_INTERVAL:
            return None
        self.last_position_ts = now
        self.positions += 1
        return (
            now, self.hex, lat, lon, alt, gs,
            as_float(ac.get("track")), dist_km, bearing, rssi,
        )


class Logger:
    def __init__(self) -> None:
        self.db = self._open_db()
        self.sessions: dict[str, Session] = {}
        self.pending_positions: list[tuple] = []
        self.running = True
        self._recover_open_sessions()

    # ---------------------------------------------------------------- setup

    def _open_db(self) -> sqlite3.Connection:
        directory = os.path.dirname(DB_PATH) or "."
        os.makedirs(directory, exist_ok=True)
        # Grafana reads this database as a different uid, and a WAL reader
        # needs write access to the -wal/-shm sidecars, so the volume is kept
        # group/other writable on purpose. It only ever exists inside a
        # private docker volume.
        os.chmod(directory, 0o777)
        db = sqlite3.connect(DB_PATH, timeout=30.0, isolation_level=None)
        db.executescript(SCHEMA)
        for suffix in ("", "-wal", "-shm"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.chmod(path, 0o666)
        return db

    def _recover_open_sessions(self) -> None:
        """Re-adopt sightings still inside the gap window after a restart."""
        cutoff = int(time.time() - SESSION_GAP)
        rows = self.db.execute(
            "SELECT id, hex, first_seen, last_seen, positions, messages "
            "FROM sighting WHERE last_seen >= ?",
            (cutoff,),
        ).fetchall()
        for row_id, hex_code, first_seen, last_seen, positions, messages in rows:
            session = Session(hex_code, last_seen, row_id=row_id)
            session.first_seen = first_seen
            session.positions = positions
            session.messages = messages
            session.dirty = False
            self.sessions[hex_code] = session
        if rows:
            LOG.info("resumed %d in-flight sightings", len(rows))

    # ------------------------------------------------------------- airlines

    def refresh_airlines(self) -> None:
        last = self.db.execute(
            "SELECT value FROM meta WHERE key = 'airlines_updated'"
        ).fetchone()
        if last and time.time() - float(last[0]) < AIRLINE_REFRESH_DAYS * 86400:
            return
        try:
            raw = fetch(AIRLINE_URL).decode("utf-8", "replace")
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            LOG.warning("airline database refresh failed: %s", exc)
            return
        rows = []
        for record in csv.reader(io.StringIO(raw)):
            # OpenFlights airlines.dat: id,name,alias,iata,icao,callsign,country,active
            if len(record) < 7:
                continue
            icao, name, country = record[4].strip(), record[1].strip(), record[6].strip()
            if len(icao) != 3 or not icao.isalpha() or icao == "N/A":
                continue
            rows.append((icao.upper(), name, country))
        if not rows:
            LOG.warning("airline database refresh returned no usable rows")
            return
        self.db.execute("BEGIN")
        self.db.executemany(
            "INSERT INTO airline (code, name, country) VALUES (?, ?, ?) "
            "ON CONFLICT(code) DO UPDATE SET name = excluded.name, "
            "country = excluded.country",
            rows,
        )
        self.db.execute(
            "INSERT INTO meta (key, value) VALUES ('airlines_updated', ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (str(time.time()),),
        )
        self.db.execute("COMMIT")
        LOG.info("airline database refreshed: %d designators", len(rows))

    def airline_name(self, code: str | None) -> str | None:
        if not code:
            return None
        row = self.db.execute(
            "SELECT name FROM airline WHERE code = ?", (code,)
        ).fetchone()
        return row[0] if row else None

    # ------------------------------------------------------------- pipeline

    def poll(self) -> None:
        try:
            payload = json.loads(fetch(JSON_URL, timeout=10.0))
        except (urllib.error.URLError, OSError, TimeoutError, ValueError) as exc:
            LOG.warning("poll failed: %s", exc)
            return

        now = int(payload.get("now") or time.time())
        for ac in payload.get("aircraft", ()):
            hex_code = (ac.get("hex") or "").strip().lower()
            if not hex_code or hex_code.startswith("~"):
                # A leading ~ marks a non-ICAO (TIS-B) address; it does not
                # identify a real airframe, so it would pollute the log.
                continue
            # "seen" is how long ago the last message from this aircraft was.
            # readsb keeps stale entries around briefly; only count fresh ones.
            seen = as_float(ac.get("seen"))
            if seen is not None and seen > SESSION_GAP:
                continue

            session = self.sessions.get(hex_code)
            if session is None or now - session.last_seen > SESSION_GAP:
                if session is not None:
                    self.flush_session(session)
                session = Session(hex_code, now)
                self.sessions[hex_code] = session

            position = session.update(ac, now)
            if position is not None:
                self.pending_positions.append(position)

    def expire(self, now: int) -> None:
        for hex_code, session in list(self.sessions.items()):
            if now - session.last_seen > SESSION_GAP:
                self.flush_session(session)
                del self.sessions[hex_code]

    def flush_session(self, session: Session) -> None:
        if not session.dirty:
            return
        values = (
            session.hex, session.first_seen, session.last_seen,
            max(0, session.last_seen - session.first_seen),
            session.callsign, session.airline_code,
            self.airline_name(session.airline_code),
            session.registration, session.icao_type, session.aircraft_desc,
            session.country, session.military, session.squawk,
            session.emergency, session.category, session.messages,
            session.positions, session.alt_min, session.alt_max,
            session.gs_max, session.rssi_max, session.dist_min_km,
            session.dist_max_km, session.bearing_closest,
            session.lat_closest, session.lon_closest,
        )
        if session.row_id is None:
            cursor = self.db.execute(
                "INSERT INTO sighting (hex, first_seen, last_seen, duration_s, "
                "callsign, airline_code, airline, registration, icao_type, "
                "aircraft_desc, country, military, squawk, emergency, category, "
                "messages, positions, alt_min, alt_max, gs_max, rssi_max, "
                "dist_min_km, dist_max_km, bearing_closest, lat_closest, "
                "lon_closest) VALUES (" + ",".join("?" * 26) + ")",
                values,
            )
            session.row_id = cursor.lastrowid
        else:
            self.db.execute(
                "UPDATE sighting SET hex = ?, first_seen = ?, last_seen = ?, "
                "duration_s = ?, callsign = ?, airline_code = ?, airline = ?, "
                "registration = ?, icao_type = ?, aircraft_desc = ?, "
                "country = ?, military = ?, squawk = ?, emergency = ?, "
                "category = ?, messages = ?, positions = ?, alt_min = ?, "
                "alt_max = ?, gs_max = ?, rssi_max = ?, dist_min_km = ?, "
                "dist_max_km = ?, bearing_closest = ?, lat_closest = ?, "
                "lon_closest = ? WHERE id = ?",
                values + (session.row_id,),
            )
        session.dirty = False

    def flush(self) -> None:
        self.db.execute("BEGIN")
        try:
            for session in self.sessions.values():
                self.flush_session(session)
            if self.pending_positions:
                # Positions are buffered until their sighting has a row id,
                # which flush_session above guarantees.
                rows = [
                    (ts, self.sessions[hex_code].row_id, hex_code, *rest)
                    for ts, hex_code, *rest in self.pending_positions
                    if hex_code in self.sessions
                    and self.sessions[hex_code].row_id is not None
                ]
                self.db.executemany(
                    "INSERT INTO position (ts, sighting_id, hex, lat, lon, alt, "
                    "gs, track, dist_km, bearing, rssi) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    rows,
                )
                self.pending_positions.clear()
            self.db.execute("COMMIT")
        except sqlite3.Error:
            self.db.execute("ROLLBACK")
            raise

    def prune(self) -> None:
        now = int(time.time())
        self.db.execute(
            "DELETE FROM position WHERE ts < ?",
            (now - POSITION_RETENTION_DAYS * 86400,),
        )
        self.db.execute(
            "DELETE FROM sighting WHERE last_seen < ?",
            (now - SIGHTING_RETENTION_DAYS * 86400,),
        )
        self.db.execute("PRAGMA incremental_vacuum")
        self.db.execute("PRAGMA optimize")

    def stop(self, *_args) -> None:
        self.running = False

    def run(self) -> None:
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
        self.refresh_airlines()

        next_flush = time.time() + FLUSH_INTERVAL
        next_prune = time.time() + 3600
        while self.running:
            started = time.time()
            self.poll()
            now = time.time()
            if now >= next_flush:
                # Flush first: expire() drops sessions from the map, and
                # buffered positions are keyed to their session's row id.
                self.flush()
                self.expire(int(now))
                next_flush = now + FLUSH_INTERVAL
            if now >= next_prune:
                self.prune()
                self.refresh_airlines()
                next_prune = now + 6 * 3600
            time.sleep(max(0.0, POLL_INTERVAL - (time.time() - started)))

        LOG.info("shutting down, flushing")
        self.flush()
        self.db.close()


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("ADSB_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    LOG.info("polling %s every %ss -> %s", JSON_URL, POLL_INTERVAL, DB_PATH)
    if not RECEIVER_SET:
        # Normally harmless: readsb supplies r_dst/r_dir whenever *its* own
        # position is set, and this is only the fallback. Worth saying out
        # loud though, because a half-configured pair silently loses every
        # distance and bearing for Mode S-only contacts.
        LOG.warning(
            "ADSB_LAT/ADSB_LON not both set (lat=%r lon=%r); falling back to "
            "readsb's r_dst/r_dir only", RECEIVER_LAT, RECEIVER_LON,
        )
    Logger().run()


if __name__ == "__main__":
    main()
