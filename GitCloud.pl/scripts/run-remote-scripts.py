from pypsrp.client import Client
import sys

# Windows server credentials
win_host = "10.241.213.224"
win_user = "administrator"
win_pass = "Kreatyna$132!ks"
scripts_path = "C:\\Gitcloud.pl\\"

# Create WinRM client
client = Client(
    win_host,
    username=win_user,
    password=win_pass,
    ssl=False,
    cert_validation=False
)

print(f"Connecting to {win_host} ...")

# 1. Get list of .ps1 files
cmd_list = f"Get-ChildItem -Path '{scripts_path}' -Filter '*.ps1' | Select-Object -ExpandProperty FullName"
stdout, stderr, rc = client.execute_cmd(cmd_list)

if rc != 0:
    print("Failed to list scripts:")
    print(stderr)
    sys.exit(1)

scripts = [line.strip() for line in stdout.splitlines() if line.strip()]

if not scripts:
    print("No scripts found in the folder.")
    sys.exit(0)

print("Found scripts:")
for s in scripts:
    print(" - " + s)

print("\nRunning scripts...\n")

# 2. Run each script
for script in scripts:
    print(f"=== Running: {script} ===")
    cmd_run = f"pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"{script}\""
    stdout, stderr, rc = client.execute_cmd(cmd_run)

    print("--- STDOUT ---")
    print(stdout)

    if stderr.strip():
        print("--- STDERR ---")
        print(stderr)

    print(f"Return code: {rc}")
    print("===========================\n")

print("All scripts executed.")
