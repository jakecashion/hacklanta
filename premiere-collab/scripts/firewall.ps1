# Host laptop only. Run from an elevated PowerShell. Opens TCP 8080 on all network profiles.
netsh advfirewall firewall add rule name="premiere-collab relay" dir=in action=allow protocol=TCP localport=8080 profile=any
