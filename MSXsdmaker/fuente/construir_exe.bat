@echo off
rem construir_exe.bat - MSXsdmaker.exe (un solo fichero, pide administrador al abrirse) con PyInstaller.
rem Lleva dentro sd\ (base, nextor-2.1.4, nextor-3.0.0-beta2, extras) y py7zr (lee el .7z del pack de KdL para el
rem MSXBOOK; el pack NO va dentro). Resultado: dist\MSXsdmaker.exe
cd /d "%~dp0"
python -m PyInstaller --noconfirm --clean --onefile --windowed --uac-admin --name MSXsdmaker ^
  --add-data "%~dp0sd\base;sd\base" --add-data "%~dp0sd\nextor-2.1.4;sd\nextor-2.1.4" ^
  --add-data "%~dp0sd\nextor-3.0.0-beta2;sd\nextor-3.0.0-beta2" --add-data "%~dp0sd\extras;sd\extras" --hidden-import py7zr ^
  --workpath build --specpath build MSXsdmaker.py
