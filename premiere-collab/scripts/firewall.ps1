# firewall.ps1 - run ONCE on the host laptop in an elevated PowerShell.
# profile=any because venue and hotspot Wi-Fi are usually marked Public.
netsh advfirewall firewall delete rule name="Live Collab relay 8080" | Out-Null
netsh advfirewall firewall add rule name="Live Collab relay 8080" dir=in action=allow protocol=TCP localport=8080 profile=any
