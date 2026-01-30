@echo off

wbAdmin delete catalog -quiet
wbAdmin start backup -backupTarget:E: -include:C: -allCritical -quiet
pause
