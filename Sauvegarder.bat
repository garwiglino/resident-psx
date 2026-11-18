@echo off
rem Double-clic : enregistre tout le projet et l'envoie sur GitHub.
cd /d "%~dp0"
set /p MSG="Note pour cette sauvegarde (Entree pour la date seule) : "
if "%MSG%"=="" set MSG=Sauvegarde du %date% %time:~0,5%
git add -A
git commit -m "%MSG%"
git push
echo.
echo Termine. Verifie qu'il n'y a pas d'erreur au-dessus.
pause
