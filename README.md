# ephemeral-tunnel
Fast disposable WireGuard VPN on GCP. Deploy in seconds, destroy when done.

## Prerequisites
- Google Cloud Platform account with billing enabled
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (`gcloud`)
- [Terraform](https://developer.hashicorp.com/terraform/install) (v0.14+)
- WireGuard client ([official clients](https://www.wireguard.com/install/))

## Usage
1. Clone this repo:
   ```
   git clone https://github.com/kennethwolters/ephemeral-tunnel.git
   cd ephemeral-tunnel
   ```

2. Deploy:
   ```
   terraform init
   terraform apply -var="project_id=YOUR_GCP_PROJECT_ID"
   ```

3. Get client config:
   ```
   gcloud compute ssh wireguard-vpn --zone=us-central1-a
   sudo su
   sudo cat /etc/wireguard/client.conf
   ```
   > **Note**: Only the root user has access to the WireGuard configuration files. Make sure to run `sudo su` before attempting to access the client configuration.

4. Copy config to your WireGuard client and connect

5. When finished:
   ```
   terraform destroy -var="project_id=YOUR_GCP_PROJECT_ID"
   ```

## Interface
**Required Arguments:**
- `project_id`: Your GCP project ID

**Optional Arguments:**
- `region`: GCP region (default: `us-central1`)
- `zone`: GCP zone (default: `us-central1-a`)

**Outputs:**
- `instance_ip`: Public IP of the VPN server
- `client_config_instructions`: Instructions to retrieve client config

## Security Notice
**This is not a hardened production VPN setup.**
- Keys are generated on the server (not ideal)
- No additional authentication mechanisms
- Permissive firewall rules (any IP can connect)
- Only meant for ephemeral use (hours, not days)
- No server-side logging or monitoring
- WireGuard configuration files are only accessible by root for security

Destroy the server when finished rather than leaving it running.
