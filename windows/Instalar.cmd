@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0nexum.ps1" Install
if errorlevel 1 pause
