@echo off
cd /d "D:\PROGRAM FILES\Data Engineer\Projects\weather-sql-pipeline"
"C:\Users\DELL\AppData\Local\Programs\Python\Python313\python.exe" ingestion\extract_load.py 2 >> pipeline_log.txt 2>&1
