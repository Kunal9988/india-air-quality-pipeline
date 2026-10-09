USE weather_dw;

-- Staging: rename, derive, drop empty rows
CREATE OR REPLACE VIEW stg_observations AS
SELECT city, obs_time, DATE(obs_time) AS obs_date, HOUR(obs_time) AS obs_hour,
       temperature_2m AS temp_c, relative_humidity_2m AS humidity_pct,
       precipitation AS rain_mm, wind_speed_10m AS wind_kmh,
       pm10, pm2_5, us_aqi
FROM raw_hourly_observations
WHERE NOT (temperature_2m IS NULL AND pm2_5 IS NULL AND us_aqi IS NULL);

-- Dimensions
CREATE TABLE IF NOT EXISTS dim_city (
  city_id INT AUTO_INCREMENT PRIMARY KEY,
  city VARCHAR(50) UNIQUE, latitude DECIMAL(8,4), longitude DECIMAL(8,4));
INSERT IGNORE INTO dim_city (city, latitude, longitude) VALUES
 ('Pune',18.52,73.86),('Mumbai',19.08,72.88),('Delhi',28.61,77.21),
 ('Bengaluru',12.97,77.59),('Chennai',13.08,80.27);

CREATE TABLE IF NOT EXISTS dim_date (
  date_key DATE PRIMARY KEY, year SMALLINT, month TINYINT, month_name VARCHAR(10),
  day_of_week TINYINT, day_name VARCHAR(10), is_weekend BOOLEAN);

SET SESSION cte_max_recursion_depth = 5000;
INSERT IGNORE INTO dim_date
WITH RECURSIVE d AS (
  SELECT DATE('2025-01-01') AS dt
  UNION ALL
  SELECT dt + INTERVAL 1 DAY FROM d WHERE dt < '2028-12-31')
SELECT dt, YEAR(dt), MONTH(dt), MONTHNAME(dt), DAYOFWEEK(dt), DAYNAME(dt),
       DAYOFWEEK(dt) IN (1,7)
FROM d;

-- Fact: one row per city per hour
CREATE OR REPLACE VIEW fact_hourly_air_weather AS
SELECT c.city_id, s.obs_date AS date_key, s.obs_hour,
       s.temp_c, s.humidity_pct, s.rain_mm, s.wind_kmh, s.pm10, s.pm2_5, s.us_aqi,
       CASE WHEN s.us_aqi IS NULL THEN 'Unknown'
            WHEN s.us_aqi <= 50  THEN 'Good'
            WHEN s.us_aqi <= 100 THEN 'Moderate'
            WHEN s.us_aqi <= 150 THEN 'Unhealthy for Sensitive Groups'
            WHEN s.us_aqi <= 200 THEN 'Unhealthy'
            WHEN s.us_aqi <= 300 THEN 'Very Unhealthy'
            ELSE 'Hazardous' END AS aqi_category
FROM stg_observations s
JOIN dim_city c ON c.city = s.city;

-- Mart: one row per city per day
CREATE OR REPLACE VIEW mart_daily_city_summary AS
SELECT c.city, f.date_key AS obs_date,
       ROUND(AVG(f.temp_c),1) AS avg_temp_c,
       ROUND(SUM(f.rain_mm),1) AS total_rain_mm,
       ROUND(AVG(f.pm2_5),1) AS avg_pm25,
       MAX(f.pm2_5) AS max_pm25,
       ROUND(AVG(f.us_aqi),0) AS avg_aqi,
       COUNT(*) AS hours_recorded
FROM fact_hourly_air_weather f
JOIN dim_city c USING (city_id)
GROUP BY c.city, f.date_key;