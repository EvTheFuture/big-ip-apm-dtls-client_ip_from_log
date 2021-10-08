![GitHub](https://img.shields.io/github/license/EvTheFuture/big-ip-apm-dtls-client_ip_from_log)
![GitHub issues](https://img.shields.io/github/issues/EvTheFuture/big-ip-apm-dtls-client_ip_from_log)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/EvTheFuture/big-ip-apm-dtls-client_ip_from_log)

# Introduction
This script is to be used if you have a BIG-IP APM installation from [F5 networks](https://www.f5.com) connected to a [Checkpoint Identity Aware Firewall](https://www.checkpoint.com/quantum/next-generation-firewall/identity-awareness/) and intend to switch from TLS to DTLS on our Client VPN connections.

When switching from a traditional TCP/TLS VPN setup in the F5 BIG-IP APM to an UDP/DTLS setup, the Edge Client will no longer get the IP address from the server by [requesting "/myvpn?sess="](https://devcentral.f5.com/s/articles/integrate-f5-ssl-vpn-with-checkpoint-identity-awareness-1149) over HTTPS, but rather get the IP address assigned from the profile configured for DTLS.

This means that the iRules used no longer work and if you have an Identity Awareness integration to your firewall, this will break when switching to DTLS.

# This script
This script aims to fix this by constantly read the end of the /var/log/apm log file and react when an IP-address has been assigned to a session.

The script will then fetch the appropriate information from the session and send it to (in this case) Checkpoint Identity Awareness Web API.

# Installation
* Copy the script `checkpoint_identity_awareness_dtls.bash` to the directory `/config` on your BIG-IP system
* Add the following line to /config/startup (replacing <address> and <secret> with your checkpoint IP adress and shared secret for the Web API) `/config/checkpoint_identity_awareness_dtls.bash -a <address> -s <secret> -d`

# Future Improvements
* Hide secret from command line (and process info) by moving configuration to a configuration file

# Feel free to contribute
* I'll gladly accept Pull requests with improvements and integration to other platforms

[![buy-me-a-coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/EvTheFuture)
