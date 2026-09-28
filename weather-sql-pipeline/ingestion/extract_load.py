import os, sys, time, requests, pandas as pd, mysql.connector

CITIES = {"Pune": (18.52, 73.86), "Mumbai": (19.08, 72.88),
          "Delhi": (28.61, 77.21), "Bengaluru": (12.97, 77.59),
          "Chennai": (13.08, 80.27)}

DB = dict(host="localhost", user=os.getenv("DB_USER", "root"),
          password=os.getenv("DB_PASSWORD", ""), database="weather_dw")

COLS = ["temperature_2m", "relative_humidity_2m", "precipitation",
        "wind_speed_10m", "pm10", "pm2_5", "us_aqi"]

def get_json(url, params, retries=3):
    for attempt in range(retries):
        try:
            r = requests.get(url, params=params, timeout=30)
            r.raise_for_status()
            return r.json()
        except requests.RequestException:
            if attempt == retries - 1:
                raise
            time.sleep(2 ** attempt)

def fetch(lat, lon, past_days):
    common = {"latitude": lat, "longitude": lon, "past_days": past_days,
              "forecast_days": 1, "timezone": "Asia/Kolkata"}
    w = get_json("https://api.open-meteo.com/v1/forecast",
        {**common, "hourly": "temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m"})
    a = get_json("https://air-quality-api.open-meteo.com/v1/air-quality",
        {**common, "hourly": "pm10,pm2_5,us_aqi"})
    df = pd.DataFrame(w["hourly"]).merge(pd.DataFrame(a["hourly"]), on="time")
    df["time"] = pd.to_datetime(df["time"]).dt.strftime("%Y-%m-%d %H:%M:%S")
    df = df.dropna(subset=COLS, how="all").drop_duplicates(subset="time")
    return df.astype(object).where(df.notna(), None)

UPSERT = """
INSERT INTO raw_hourly_observations
 (city, obs_time, temperature_2m, relative_humidity_2m, precipitation,
  wind_speed_10m, pm10, pm2_5, us_aqi)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
 temperature_2m=VALUES(temperature_2m), relative_humidity_2m=VALUES(relative_humidity_2m),
 precipitation=VALUES(precipitation), wind_speed_10m=VALUES(wind_speed_10m),
 pm10=VALUES(pm10), pm2_5=VALUES(pm2_5), us_aqi=VALUES(us_aqi), loaded_at=NOW()
"""

CHECKS = {
  "humidity_out_of_range":
    "SELECT COUNT(*) FROM raw_hourly_observations WHERE relative_humidity_2m NOT BETWEEN 0 AND 100",
  "negative_pm25":
    "SELECT COUNT(*) FROM raw_hourly_observations WHERE pm2_5 < 0",
  "days_with_missing_hours":
    """SELECT COUNT(*) FROM (SELECT city, DATE(obs_time) d, COUNT(*) c
       FROM raw_hourly_observations WHERE DATE(obs_time) < CURDATE()
       GROUP BY city, d HAVING c < 24) x""",
}

def main(past_days):
    conn = mysql.connector.connect(**DB)
    cur = conn.cursor()
    for city, (lat, lon) in CITIES.items():
        try:
            df = fetch(lat, lon, past_days)
            rows = [(city, *r) for r in df.itertuples(index=False, name=None)]
            cur.executemany(UPSERT, rows)
            conn.commit()
            status, n, err = "SUCCESS", len(rows), None
        except Exception as e:
            conn.rollback()
            status, n, err = "FAILED", 0, str(e)
        cur.execute("INSERT INTO pipeline_run_log (city, rows_upserted, status, error_message) "
                    "VALUES (%s,%s,%s,%s)", (city, n, status, err))
        conn.commit()
        print(f"{city}: {status} ({n} rows)")

    failed = False
    for name, sql in CHECKS.items():
        cur.execute(sql)
        bad = cur.fetchone()[0]
        print(f"CHECK {name}: {'OK' if bad == 0 else f'FAILED ({bad})'}")
        failed |= bad > 0
    conn.close()
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 2)