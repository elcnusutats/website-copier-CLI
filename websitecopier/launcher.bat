@echo off
:: Force the terminal into UTF-8 mode so it can display the block ASCII art correctly
chcp 65001 >nul
color 0A
title WEBSITE COPIER

:MAINMENU
cls
echo =======================================================================================================
echo ██╗    ██╗███████╗██████╗ ███████╗██╗████████╗███████╗    ██████╗  ██████╗ ██████╗ ██╗███████╗██████╗ 
echo ██║    ██║██╔════╝██╔══██╗██╔════╝██║╚══██╔══╝██╔════╝    ██╔════╝ ██╔═══██╗██╔══██╗██║██╔════╝██╔══██╗
echo ██║ █╗ ██║█████╗  ██████╔╝███████╗██║   ██║   █████╗      ██║      ██║   ██║██████╔╝██║█████╗  ██████╔╝
echo ██║███╗██║██╔══╝  ██╔══██╗╚════██║██║   ██║   ██╔══╝      ██║      ██║   ██║██╔═══╝ ██║██╔══╝  ██╔══██╗
echo ╚███╔███╔╝███████╗██████╔╝███████║██║   ██║   ███████╗    ╚██████╗ ╚██████╔╝██║     ██║███████╗██║  ██║
echo  ╚══╝╚══╝ ╚══════╝╚═════╝ ╚══════╝╚═╝   ╚═╝   ╚══════╝     ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝
echo =======================================================================================================
echo hey, im elcnusutats and i made this tool...
echo.
echo choose an option below:
echo [1] copy/clone a website
echo [2] delete an old clone/copy folder
echo [3] exit
echo =======================================================================================================
echo.

set /p userChoice="put the number of your choice: "

if "%userChoice%"=="1" goto CLONE
if "%userChoice%"=="2" goto CLEAN
if "%userChoice%"=="3" goto EXIT_APP
goto MAINMENU

:CLONE
echo.
echo =======================================================================================================
set /p targetUrl="enter the FULL target URL (e.g., https://www.youtube.com) please actually dont put that in: "
echo.
echo starting script...
echo =======================================================================================================
dotnet run "%targetUrl%"
echo.
echo script finished. press any key to return to the menu.
pause >nul
goto MAINMENU

:CLEAN
echo.
echo =======================================================================================================
set /p folderName="put the exact name of the folder you want to delete (e.g., www.youtube.com this is also a joke): "
echo Deleting folder %folderName%...
rmdir /S /Q "%folderName%"
echo folder got nuked (that is a joke)
echo =======================================================================================================
pause >nul
goto MAINMENU

:EXIT_APP
echo.
echo good bye
timeout /t 2 >nul
exit