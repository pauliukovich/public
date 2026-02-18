from pypsrp.client import Client
import subprocess

# Windows server credentials (WinRM target)
win_host = "10.241.30.138"
win_user = "Administrator"
win_pass = "Kreatyna$132!ks"

# Local folder on Linux
local_folder = "/home/gitcloud/database/serwer-spn/"

# Create WinRM client
client = Client(win_host, username=win_user, password=win_pass, ssl=False, auth="ntlm")

# PowerShell command to zip the folder and send as base64
command = """
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = 'C:\\Temp\\database.zip'
if (Test-Path $zip) { Remove-Item $zip }
[System.IO.Compression.ZipFile]::CreateFromDirectory('C:\\Windows\\database\\', $zip)
[Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
"""

stdout, stderr, rc = client.execute_ps(command)

if rc == 0:
    with open("/tmp/database2.zip.b64", "w") as f:
        f.write(stdout)
else:
    print("Error:", stderr)
    exit()

subprocess.run("base64 -d /tmp/database2.zip.b64 > /tmp/database2.zip", shell=True)
subprocess.run(f"unzip -o /tmp/database2.zip -d {local_folder}", shell=True)
print("Sync2 completed.")
