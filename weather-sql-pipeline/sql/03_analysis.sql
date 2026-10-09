USE weather_dw;

-- 1. Rolling 7-day average PM2.5 per city
SELECT city, obs_date, avg_pm25,
  ROUND(AVG(avg_pm25) OVER (PARTITION BY city ORDER BY obs_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS pm25_7d_avg
FROM mart_daily_city_summary
ORDER BY city, obs_date;

-- 2. Which city was most polluted each day
SELECT obs_date, city, avg_aqi,
  RANK() OVER (PARTITION BY obs_date ORDER BY avg_aqi DESC) AS pollution_rank
FROM mart_daily_city_summary
ORDER BY obs_date, pollution_rank;

-- 3. Day-over-day change in PM2.5
SELECT city, obs_date, avg_pm25,
  avg_pm25 - LAG(avg_pm25) OVER (PARTITION BY city ORDER BY obs_date) AS change_vs_prev_day
FROM mart_daily_city_summary
ORDER BY city, obs_date;

-- 4. Worst 3 days per city (CTE + ROW_NUMBER)
WITH ranked AS (
  SELECT city, obs_date, avg_pm25,
    ROW_NUMBER() OVER (PARTITION BY city ORDER BY avg_pm25 DESC) AS rn
  FROM mart_daily_city_summary)
SELECT * FROM ranked WHERE rn <= 3 ORDER BY city, rn;

-- 5. Anomaly days: more than 2 standard deviations above the city's mean
WITH stats AS (
  SELECT city, obs_date, avg_pm25,
    AVG(avg_pm25) OVER (PARTITION BY city) AS mean_pm25,
    STDDEV_SAMP(avg_pm25) OVER (PARTITION BY city) AS sd_pm25
  FROM mart_daily_city_summary)
SELECT * FROM stats WHERE avg_pm25 > mean_pm25 + 2 * sd_pm25;

-- 6. Pollution streaks: 3+ consecutive days with AQI > 100 (gaps-and-islands)
WITH flagged AS (
  SELECT city, obs_date FROM mart_daily_city_summary WHERE avg_aqi > 100),
grp AS (
  SELECT city, obs_date,
    DATE_SUB(obs_date, INTERVAL ROW_NUMBER() OVER (PARTITION BY city ORDER BY obs_date) DAY) AS grp_key
  FROM flagged)
SELECT city, MIN(obs_date) AS streak_start, MAX(obs_date) AS streak_end, COUNT(*) AS days
FROM grp GROUP BY city, grp_key HAVING COUNT(*) >= 3
ORDER BY days DESC;