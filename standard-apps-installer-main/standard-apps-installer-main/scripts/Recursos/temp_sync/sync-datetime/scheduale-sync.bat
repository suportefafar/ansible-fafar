@echo off

:: Name of the task
set TASKNAME=SyncTimeAtLogon

:: Path to your silent sync script
set SCRIPT=C:\sync-datetime\sync-datetime.bat

:: Delete existing task if it exists
schtasks /Delete /TN "%TASKNAME%" /F >nul 2>&1

:: Create a new task to run at logon with highest privileges
schtasks /Create /TN "%TASKNAME%" /TR "\"%SCRIPT%\"" /SC ONLOGON /RL HIGHEST /F

echo Task "%TASKNAME%" created successfully.
exit
