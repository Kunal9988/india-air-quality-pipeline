CREATE DATABASE IF NOT EXISTS weather_dw;
USE weather_dw;

CREATE TABLE IF NOT EXISTS raw_hourly_observations (
  city VARCHAR(50) NOT NULL,
  obs_time DATETIME NOT NULL,
  temperature_2m FLOAT, relative_humidity_2m FLOAT,
  precipitation FLOAT, wind_speed_10m FLOAT,
  pm10 FLOAT, pm2_5 FLOAT, us_aqi FLOAT,
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (city, obs_time)
);

CREATE TABLE IF NOT EXISTS pipeline_run_log (
  run_id INT AUTO_INCREMENT PRIMARY KEY,
  run_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  city VARCHAR(50),
  rows_upserted INT,
  status VARCHAR(10),
  error_message TEXT
);