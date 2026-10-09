USE weather_dw;

-- Worst single day
SELECT city, obs_date, avg_pm25, max_pm25
FROM mart_daily_city_summary
ORDER BY avg_pm25 DESC
LIMIT 1;

-- Anomaly days (more than 2 standard deviations above the city's mean)
WITH stats AS (
  SELECT city, obs_date, avg_pm25,
    AVG(avg_pm25) OVER (PARTITION BY city) AS mean_pm25,
    STDDEV_SAMP(avg_pm25) OVER (PARTITION BY city) AS sd_pm25
  FROM mart_daily_city_summary)
SELECT city, obs_date, avg_pm25, ROUND(mean_pm25,1) AS city_mean
FROM stats WHERE avg_pm25 > mean_pm25 + 2 * sd_pm25;

-- Pollution streaks (3+ consecutive days with AQI above 100)
WITH flagged AS (
  SELECT city, obs_date FROM mart_daily_city_summary WHERE avg_aqi > 100),
grp AS (
  SELECT city, obs_date,
    DATE_SUB(obs_date, INTERVAL ROW_NUMBER() OVER (PARTITION BY city ORDER BY obs_date) DAY) AS grp_key
  FROM flagged)
SELECT city, MIN(obs_date) AS streak_start, MAX(obs_date) AS streak_end, COUNT(*) AS days
FROM grp GROUP BY city, grp_key HAVING COUNT(*) >= 3
ORDER BY days DESC;