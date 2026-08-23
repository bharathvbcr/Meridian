#!/usr/bin/env python3
# devcouncil: allow-unwired — data-build CLI (also declared in pyproject scripts)
"""
Generate the bundled `cities.db` SQLite database that powers Meridian's
"every city" location search, from the open GeoNames dataset.

The app's searchable unit is an IANA time zone (a SavedZone is keyed by zone id),
so this database is fundamentally a *name -> zone resolver*: type any city/town in
the world and it resolves to the correct IANA zone, labelled with that city's name.

Sources:
  - GeoNames (CC-BY 4.0): https://download.geonames.org/export/dump/
      cities{500,1000,5000,15000}.zip  -- populated places above that population
      countryInfo.txt                  -- ISO country code -> country name
  - OpenFlights (ODbL): https://github.com/jpatokal/openflights
      airports.dat                     -- IATA airport code -> IANA time zone

Run:
    python build_cities_db.py --tier 500        # most comprehensive (~all towns)
    python build_cities_db.py --tier 5000       # cities & larger towns

Output:
    cities.db  (and copied to ../../app/src/main/assets/cities.db)

The schema is intentionally tiny and self-contained (no Room metadata) so the app
can open it directly read-only:

    CREATE TABLE city(
        name        TEXT NOT NULL COLLATE NOCASE,  -- display name (native/common), e.g. "Zürich"
        name_lower  TEXT NOT NULL COLLATE NOCASE,  -- diacritic-folded name, prefix-searched ("zurich")
        ascii_lower TEXT NOT NULL COLLATE NOCASE,  -- folded GeoNames asciiname when it differs, else ""
        country     TEXT NOT NULL,                 -- e.g. "Switzerland"
        zone        TEXT NOT NULL,                 -- IANA id, e.g. "Europe/Zurich"
        population  INTEGER NOT NULL               -- for ranking (bigger first)
    );
    CREATE INDEX idx_city_name_lower ON city(name_lower COLLATE NOCASE);
    CREATE INDEX idx_city_ascii_lower ON city(ascii_lower COLLATE NOCASE);

    -- name_lower folds the native name so "zurich" matches "Zürich"; ascii_lower keeps the
    -- GeoNames romanization (e.g. German "Zuerich", or "Tokyo" for native "東京") for the cases
    -- where the asciiname transliterates rather than just dropping diacritics.

    CREATE TABLE airport(
        iata        TEXT NOT NULL,                 -- "SFO"
        iata_lower  TEXT NOT NULL COLLATE NOCASE,
        name        TEXT NOT NULL,                 -- "San Francisco International Airport"
        name_lower  TEXT NOT NULL COLLATE NOCASE,
        city        TEXT NOT NULL,                 -- "San Francisco"
        country     TEXT NOT NULL,
        zone        TEXT NOT NULL                  -- IANA id
    );
    CREATE INDEX idx_airport_iata ON airport(iata_lower COLLATE NOCASE);

`schema_meta(version)` carries a bundle version so the app re-copies the asset
when it changes.
"""
import argparse
import csv
import os
import shutil
import sqlite3
import sys
import time
import unicodedata
import urllib.request
import zipfile

BUNDLE_VERSION = 2  # bump when regenerating with a different tier/schema
GEONAMES = "https://download.geonames.org/export/dump"
OPENFLIGHTS = "https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat"
HERE = os.path.dirname(os.path.abspath(__file__))
ASSET_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "app", "src", "main", "assets"))


def fold(text: str) -> str:
    """Lowercase + strip diacritics, mirroring GeoPlaceRepository.fold() in the app
    (NFD normalize, drop combining marks, lowercase) so the bundled keys match queries."""
    decomposed = unicodedata.normalize("NFD", text)
    stripped = "".join(c for c in decomposed if unicodedata.category(c) != "Mn")
    return stripped.lower().strip()


def download(url: str, dest: str, attempts: int = 3) -> None:
    """Downloads [url] to [dest] atomically: bytes land in a .part file and are renamed
    into place only after a complete, non-empty transfer, so an interrupted download can
    never poison the cache (a truncated zip previously passed this function's cache check
    and then failed much later with an opaque BadZipFile)."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print(f"  cached  {os.path.basename(dest)} ({os.path.getsize(dest):,} bytes)")
        return
    tmp_path = dest + ".part"
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            print(f"  GET     {url}" + ("  (retry)" if attempt > 1 else ""))
            req = urllib.request.Request(url, headers={"User-Agent": "meridian-citygen/1.0"})
            with urllib.request.urlopen(req, timeout=300) as r, open(tmp_path, "wb") as f:
                shutil.copyfileobj(r, f)
            size = os.path.getsize(tmp_path)
            if size == 0:
                raise RuntimeError("server returned 0 bytes")
            os.replace(tmp_path, dest)
            print(f"          -> {dest} ({size:,} bytes)")
            return
        except Exception as e:
            last_error = e
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
            if attempt < attempts:
                time.sleep(2 * attempt)
    raise RuntimeError(f"giving up on {url} after {attempts} attempts: {last_error!r}") from last_error


def extract_member(zip_path: str, member: str, target_dir: str, url: str) -> None:
    """Extracts one archive member, transparently recovering from a corrupt cached zip."""
    try:
        with zipfile.ZipFile(zip_path) as z:
            z.extract(member, target_dir)
    except (zipfile.BadZipFile, KeyError) as e:
        print(f"  {zip_path} is unreadable ({e!r}); discarding cache and re-downloading.")
        os.remove(zip_path)
        download(url, zip_path)
        with zipfile.ZipFile(zip_path) as z:
            z.extract(member, target_dir)


def load_country_names(path: str) -> dict:
    """ISO-3166 alpha-2 code -> country name, from countryInfo.txt."""
    names = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) > 4 and cols[0]:
                names[cols[0]] = cols[4]
    return names


def load_airports(path: str) -> list:
    """Parse OpenFlights airports.dat -> rows of (iata, iata_lower, name, name_lower,
    city, country, zone). Only airports with a real 3-letter IATA code and a known
    IANA time zone are kept."""
    rows = []
    seen = set()
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        for cols in csv.reader(f):
            if len(cols) < 12:
                continue
            name, city, country, iata = cols[1], cols[2], cols[3], cols[4]
            zone = cols[11]
            if not iata or iata == "\\N" or len(iata) != 3 or not iata.isalpha():
                continue
            if not zone or zone == "\\N":
                continue
            iata = iata.upper()
            if iata in seen:
                continue
            seen.add(iata)
            rows.append((iata, iata.lower(), name, fold(name),
                         city or country, country, zone))
    return rows


def build(tier: int) -> str:
    zip_name = f"cities{tier}.zip"
    txt_name = f"cities{tier}.txt"
    zip_path = os.path.join(HERE, zip_name)
    txt_path = os.path.join(HERE, txt_name)
    country_path = os.path.join(HERE, "countryInfo.txt")
    airports_path = os.path.join(HERE, "airports.dat")
    db_path = os.path.join(HERE, "cities.db")

    print("Downloading sources...")
    download(f"{GEONAMES}/countryInfo.txt", country_path)
    download(f"{GEONAMES}/{zip_name}", zip_path)
    download(OPENFLIGHTS, airports_path)
    if not os.path.exists(txt_path):
        print(f"Extracting {zip_name}...")
        extract_member(zip_path, txt_name, HERE, f"{GEONAMES}/{zip_name}")

    countries = load_country_names(country_path)
    print(f"Loaded {len(countries)} country names.")

    # Collapse same-name-in-same-zone duplicates to the most-populous representative,
    # so the long tail of identically named villages doesn't bloat the DB or results.
    # key: (name_lower, zone) -> (name, name_lower, ascii_lower, country, zone, population)
    best: dict = {}
    total = 0
    with open(txt_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 18:
                continue
            total += 1
            name = cols[1].strip()          # native/common name (display), e.g. "Zürich"
            asciiname = cols[2].strip()      # GeoNames romanization, e.g. "Zuerich"
            cc = cols[8].strip()
            zone = cols[17].strip()
            if not name or not zone:
                continue
            try:
                population = int(cols[14]) if cols[14] else 0
            except ValueError:
                population = 0
            name_lower = fold(name)
            if not name_lower:
                continue
            ascii_lower = fold(asciiname)
            if ascii_lower == name_lower:
                ascii_lower = ""             # avoid storing the same key twice
            country = countries.get(cc, cc)
            key = (name_lower, zone)
            prev = best.get(key)
            if prev is None or population > prev[5]:
                best[key] = (name, name_lower, ascii_lower, country, zone, population)

    rows = list(best.values())
    kept = len(rows)
    print(f"Parsed {total:,} city rows -> {kept:,} unique (name, zone) places.")

    airports = load_airports(airports_path)
    print(f"Parsed {len(airports):,} airports with IATA code + IANA zone.")

    if os.path.exists(db_path):
        os.remove(db_path)
    con = sqlite3.connect(db_path)
    try:
        cur = con.cursor()
        cur.execute("PRAGMA page_size=4096")
        cur.execute("PRAGMA journal_mode=OFF")
        cur.execute(
            "CREATE TABLE city("
            " name TEXT NOT NULL COLLATE NOCASE,"
            " name_lower TEXT NOT NULL COLLATE NOCASE,"
            " ascii_lower TEXT NOT NULL COLLATE NOCASE,"
            " country TEXT NOT NULL,"
            " zone TEXT NOT NULL,"
            " population INTEGER NOT NULL)"
        )
        cur.execute(
            "CREATE TABLE airport("
            " iata TEXT NOT NULL,"
            " iata_lower TEXT NOT NULL COLLATE NOCASE,"
            " name TEXT NOT NULL,"
            " name_lower TEXT NOT NULL COLLATE NOCASE,"
            " city TEXT NOT NULL,"
            " country TEXT NOT NULL,"
            " zone TEXT NOT NULL)"
        )
        cur.execute("CREATE TABLE schema_meta(version INTEGER NOT NULL)")
        cur.execute("INSERT INTO schema_meta(version) VALUES(?)", (BUNDLE_VERSION,))
        cur.executemany(
            "INSERT INTO city(name, name_lower, ascii_lower, country, zone, population)"
            " VALUES(?,?,?,?,?,?)",
            rows,
        )
        cur.executemany(
            "INSERT INTO airport(iata, iata_lower, name, name_lower, city, country, zone)"
            " VALUES(?,?,?,?,?,?,?)",
            airports,
        )
        con.commit()
        cur.execute("CREATE INDEX idx_city_name_lower ON city(name_lower COLLATE NOCASE)")
        cur.execute("CREATE INDEX idx_city_ascii_lower ON city(ascii_lower COLLATE NOCASE)")
        cur.execute("CREATE INDEX idx_airport_iata ON airport(iata_lower COLLATE NOCASE)")
        con.commit()
        cur.execute("VACUUM")
        con.commit()
    except Exception:
        # Never strand a handle on a half-built db: close it and remove the partial file
        # so a later run starts clean instead of tripping over corrupt tables.
        con.close()
        if os.path.exists(db_path):
            os.remove(db_path)
        raise
    finally:
        con.close()

    size = os.path.getsize(db_path)
    print(f"\nBuilt {db_path}")
    print(f"  cities: {kept:,}   airports: {len(airports):,}")
    print(f"  size: {size/1_048_576:.1f} MiB ({size:,} bytes)")
    return db_path


def copy_to_assets(db_path: str) -> None:
    os.makedirs(ASSET_DIR, exist_ok=True)
    dest = os.path.join(ASSET_DIR, "cities.db")
    with open(db_path, "rb") as s, open(dest, "wb") as d:
        d.write(s.read())
    print(f"Copied -> {dest} ({os.path.getsize(dest):,} bytes)")


def main() -> int:
    ap = argparse.ArgumentParser(description="Build Meridian's bundled cities.db from GeoNames.")
    ap.add_argument("--tier", type=int, default=500, choices=[500, 1000, 5000, 15000],
                    help="GeoNames population tier (500 = most comprehensive). Default 500.")
    ap.add_argument("--no-copy", action="store_true", help="Build only; do not copy into app assets.")
    args = ap.parse_args()
    db_path = build(args.tier)
    if not args.no_copy:
        copy_to_assets(db_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
