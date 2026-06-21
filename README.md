# website cloner/copier CLI

hey, we made this because i was bored but most importantly, i made this so copying websites is way easier instead of downloading every image and copying code.

## what it does

* **multithreaded engine:** this will save time, it loads around 5 or 6 pages instead of one, how it works, it basically does the task on diffrent CPU cores.
* **file names, verification of files:** fixes random file names, random question marks, so windows doesnt crashout.

## how to run this thing

1. make sure you have the .net sdk installed on your computer, (https://dotnet.microsoft.com/en-us/download)
2. go to the latest release and download it.
3. double-click `launcher.bat` 
4. pick option 1, paste your target url (like https://elcnusutats.netlify.app/), and hit enter.

## notes
    
* this only rips the front-end html, css, and images/gifs.
* built with c# and htmlagilitypack.
