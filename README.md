# India Air Quality & Weather Data Pipeline

An automated ELT pipeline that pulls hourly weather and air-quality data for five Indian cities from the Open-Meteo API, loads it into MySQL, models it into a star schema, and analyzes it with SQL window functions and CTEs. Results are shown in a Power BI dashboard.

**Stack:** Python (requests, Pandas) · MySQL 8 · SQL (window functions, CTEs) · Power BI · Windows Task Scheduler

**Scale:** 5 cities · 65 days (10 Aug to 13 Oct 2026) · 7,800 hourly records

## Architecture

```text
Open-Meteo API (weather + air quality)
        |
        v
Python: fetch, clean, retry on failure        ingestion/extract_load.py
        |
        v
MySQL: raw_hourly_observations  (upsert on city + hour)
        |------> pipeline_run_log  (status and row count per run)
        v
SQL views: staging -> dim_city / dim_date -> fact_hourly_air_weather -> mart_daily_city_summary
        |
        v
Window-function analysis (sql/)  +  Power BI dashboard
```

The loader runs daily through Windows Task Scheduler (`run_pipeline.bat`).

## Dashboard

![Dashboard overview](weather-sql-pipeline/dashboard/screenshots/overview.png)

## Key findings

| City | Average daily PM2.5 (µg/m³) |
|---|---|
| Delhi | 63.9 |
| Mumbai | 23.5 |
| Chennai | 20.1 |
| Pune | 16.5 |
| Bengaluru | 14.7 |

- **Delhi is the most polluted city by far.** Its average PM2.5 is more than 4x Bengaluru's.
- **Worst day:** Delhi on 29 Aug 2026, with a daily average PM2.5 of 114.7 and an hourly peak of 165.3.
- **Pollution streaks (3+ days with AQI above 100):** 8 streaks in total. Delhi had four (24, 15, 13 and 6 days), covering 58 of the 65 days. Its longest ran from 10 Aug to 2 Sep. Mumbai had a 14-day streak (30 Sep to 13 Oct), Pune had 8-day and 4-day streaks, and Chennai had a 4-day streak.
- **Anomaly days:** 20 city-days were more than 2 standard deviations above that city's own mean. Chennai, Pune, Bengaluru and Mumbai all had anomaly days between 28 Sep and 2 Oct, which suggests a regional episode. I have not investigated the cause.

## Design decisions

- **Idempotent loads.** `raw_hourly_observations` has a composite primary key of `(city, obs_time)` and every load uses `ON DUPLICATE KEY UPDATE`. Re-running the loader never creates duplicates.
- **Overlapping load window.** Daily runs fetch the last 2 days so late-arriving corrections are picked up. The upsert makes the overlap safe.
- **Run log.** Every city load writes its status, row count and any error to `pipeline_run_log`, so failures are visible.
- **Data quality checks.** After each load the script checks for humidity outside 0 to 100, negative PM2.5, and days with fewer than 24 hourly records. It exits with an error if a check fails.
- **Layered model.** Raw table, then a staging view, then a star schema (one fact view and two dimensions), then a daily mart that Power BI reads. The date dimension is built with a recursive CTE.
- **No secrets in the repo.** The database login is read from the `DB_USER` and `DB_PASSWORD` environment variables.

### Proof it works

Re-running the loader processed 7,320 rows but grew the table by only 480, the new hours since the previous load. No duplicates were created.

![Row counts before and after a re-run](dashboard/screenshots/row_counts.png)

![Pipeline run log](dashboard/screenshots/run_log.png)

Star schema: `docs/star_schema.png`

## How to run (Windows PowerShell)

Requirements: MySQL 8.0+, Python 3.10+.

```powershell
# 1. Install dependencies
pip install -r requirements.txt

# 2. Create the database and tables
Get-Content sql/01_schema.sql | mysql -u root -p

# 3. Set credentials for this window
$env:DB_USER="root"
$env:DB_PASSWORD='your_mysql_password'

# 4. First load (about 60 days of history)
python ingestion/extract_load.py 60

# 5. Build the staging, dimension, fact and mart layers
Get-Content sql/02_model.sql | mysql -u root -p

# 6. Run the analysis
Get-Content sql/findings.sql | mysql -u root -p
```

On Mac or Linux, use `mysql -u root -p < sql/01_schema.sql` instead of `Get-Content`.

**Daily schedule:** edit the paths in `run_pipeline.bat`, then run
`schtasks /Create /TN "weather pipeline" /SC DAILY /ST 09:00 /TR "<full path to run_pipeline.bat>"`.
Save `DB_USER` and `DB_PASSWORD` as user environment variables first so the scheduled task can read them.

## Project structure

```text
sql/            01_schema.sql, 02_model.sql, 03_analysis.sql, findings.sql
ingestion/      extract_load.py
dashboard/      weather_dashboard.pbix, screenshots/
docs/           star_schema.png
run_pipeline.bat
requirements.txt
```

## Limitations

- The scheduled run only works while the laptop is on and MySQL is running. A production version would use a managed scheduler such as Airflow and a cloud warehouse.
- The data covers 65 days (late monsoon into autumn), so it supports no seasonal or yearly conclusions.
- Open-Meteo's air-quality figures are model-based estimates, not readings from ground monitoring stations. The latest day also includes forecast hours.
- Anomalies are measured against each city's own average, so a flagged day in a clean city can still have moderate absolute pollution.
- Delhi's longest streak begins on the first day of data, so it may have started earlier.
- The Power BI file is refreshed manually.

## Possible next steps

Add Docker for MySQL, move scheduling to Airflow, load a longer history, and add alerting when a quality check fails.
