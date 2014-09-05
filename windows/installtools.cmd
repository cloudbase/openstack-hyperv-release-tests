@powershell -NoProfile -ExecutionPolicy unrestricted -Command "iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))" && SET PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin

cinst notepadplusplus.install
cinst git.install

setx /m PATH "%PATH%;c:\Program Files (x86)\Git\bin;c:\Program Files (x86)\Notepad++"
