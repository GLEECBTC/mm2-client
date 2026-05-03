# Production Deployment Guide

This document describes how to deploy `mm2-client` and the supporting price
service in a production-grade environment. It assumes you plan to run the
tooling on a dedicated Linux host and manage it with systemd.

---

## 1. Scope and Architecture

- **mm2 CLI (`cmd/mm2_cli_native`)** – interactive console that initializes mm2,
  enables coins, and drives the simple market maker bot.
- **mm2 tools server (`cmd/mm2_tools_server`)** – exposes HTTP APIs that can
  start/stop the bot and optionally serve ticker data through the built-in
  price service.
- **Price service only mode** – used to publish consolidated prices to other
  nodes via `-only_price_service=true`.
- **Automation scripts** – `run_prices.sh` and `update_coins.sh` orchestrate
  service restarts and daily coins list refreshes.

You can mix these components based on your needs. The production baseline is to
run the price service as a systemd unit and operate the CLI from a hardened
jump host.

---

## 2. Prerequisites

| Requirement | Details |
|-------------|---------|
| OS | 64-bit Ubuntu 20.04/22.04 (or compatible). |
| Access | sudo-capable shell user, outbound internet access to GitHub and price feeds. |
| Toolchain | Go 1.20+ (project targets 1.16; newer Go versions are compatible), Git, curl/wget, build-essential. |
| Firewall | Allow inbound access only to required ports (e.g. 1313 for ticker API). |

Install the base toolchain:

```bash
sudo apt-get update
sudo apt-get install -y build-essential git curl wget pkg-config ufw
curl -OL https://golang.org/dl/go1.21.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/go.sh
source /etc/profile.d/go.sh
```

---

## 3. Prepare the Host

1. **Create a dedicated user and directories**
   ```bash
   sudo useradd --create-home --shell /bin/bash mm2
   sudo mkdir -p /opt/mm2-client /var/log/mm2-client
   sudo chown -R mm2:mm2 /opt/mm2-client /var/log/mm2-client
   ```
2. **Clone the repository**
   ```bash
   sudo -u mm2 git clone https://github.com/Milerius/mm2-client /opt/mm2-client
   cd /opt/mm2-client
   sudo -u mm2 git checkout $(git describe --tags --abbrev=0) # lock to latest tag
   ```
3. **Baseline security**
   - Enable `ufw` and allow SSH plus the ports you expose.
   - Keep the host updated (`unattended-upgrades` or a patch cadence).
   - Store secrets (API keys, mm2 seed) outside the repo with root-only ACLs.

---

## 4. Build Artifacts

Run the builds as the `mm2` user:

```bash
cd /opt/mm2-client
sudo -u mm2 /usr/local/go/bin/go build -o bin/mm2_client ./cmd/mm2_cli_native
sudo -u mm2 /usr/local/go/bin/go build -o bin/mm2_tools_server ./cmd/mm2_tools_server
```

Resulting binaries:

| Binary | Purpose | Example invocation |
|--------|---------|--------------------|
| `bin/mm2_client` | Interactive CLI that talks to local mm2. | `./bin/mm2_client` |
| `bin/mm2_tools_server` | HTTP service & price engine. | `./bin/mm2_tools_server -only_price_service=true` |

---

## 5. Configuration and Secrets

1. **Market maker template** – copy and edit:
   ```bash
   cp assets/simple_market_bot.template.json mm2/simple_market_bot.json
   chmod 600 mm2/simple_market_bot.json
   ```
2. **Coins configuration** – keep `coins_config.json` in the repo root updated
   (see section 8).
3. **Environment variables** – required for external price providers:

   | Variable | Description |
   |----------|-------------|
   | `LCW_API_KEY` | LiveCoinWatch API key. |
   | `GECKO_API_KEY` | Coingecko key (optional, improves rate limits). |
   | `PAPRIKA_API_KEY` | CoinPaprika API key. |

   Store them in `/etc/mm2-client.env` with `chmod 600`:
   ```
   LCW_API_KEY=***
   GECKO_API_KEY=***
   PAPRIKA_API_KEY=***
   ```

4. **mm2 state directory** – the CLI expects `~/mm2` for configs, wallet seed,
   and logs. Ensure the directory is on encrypted storage if you hold funds.

---

## 6. Operating the CLI

Run the CLI from the jump host:

```bash
cd /opt/mm2-client
bin/mm2_client
> help
> init
> start
> enable_active_coins
> start_simple_market_maker_bot
```

Guidelines:
- Use `enable COIN_A COIN_B` the first time a pair is missing.
- Validate `get_binance_supported_pairs <COIN>` before starting automated
  strategies.
- Stop gracefully with `stop_simple_market_maker_bot`, `stop`, then `exit`.

Monitor activity from another terminal:

```bash
tail -f ~/.atomicdex_cli/logs/mm2.client.log
```

---

## 7. Price Service as a Systemd Unit

Create `/etc/systemd/system/prices-gleec-com.service`:

```ini
[Unit]
Description=mm2 price service
After=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
User=mm2
Group=mm2
WorkingDirectory=/opt/mm2-client
EnvironmentFile=/etc/mm2-client.env
ExecStart=/opt/mm2-client/bin/mm2_tools_server -only_price_service=true
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/mm2-client/prices.log
StandardError=append:/var/log/mm2-client/prices.log

[Install]
WantedBy=multi-user.target
```

Then enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now prices-gleec-com.service
```

Health check endpoint:

```bash
curl http://127.0.0.1:1313/api/v2/tickers?expire_at=600
```

---

## 8. Automated Coins Updates

Use `update_coins.sh` to pull the latest `coins` list and `coins_config.json`,
then rebuild and restart the service. Install a root cron job:

```bash
sudo cp update_coins.sh /usr/local/bin/mm2-update-coins
sudo chmod 755 /usr/local/bin/mm2-update-coins
sudo crontab -e
# m h dom mon dow command
15 2 * * * /usr/local/bin/mm2-update-coins >> /var/log/mm2-client/coins-update.log 2>&1
```

This script:
1. Downloads the latest `coins` file.
2. Backs up `coins_config.json` before replacing it.
3. Rebuilds `bin/mm2_tools_server`.
4. Restarts the systemd service.

---

## 9. Logging and Observability

- `journalctl -u prices-gleec-com -f` – follow service logs.
- `/var/log/mm2-client/prices.log` – consolidated stdout/stderr.
- `~/.atomicdex_cli/logs/mm2.client.log` – CLI bot activity.
- Add logrotate entries for the log directory if retention is required.
- Optionally forward metrics to a central system by scraping the ticker API or
  wrapping it with Prometheus exporters.

---

## 10. Backups and Recovery

| Item | Location | Notes |
|------|----------|-------|
| Wallet seeds & mm2 cfg | `/home/mm2/mm2/` | Encrypt or store offline; treat as critical secret. |
| Market maker config | `/opt/mm2-client/mm2/simple_market_bot.json` | Version control changes in a private repo. |
| Coins metadata | `/opt/mm2-client/coins_config.json` | Automatically rebuilt but keep last known-good copy. |

Automated backups can rsync sensitive files to an encrypted volume or remote
vault. Verify restores quarterly.

---

## 11. Hardening Checklist

- Use `ufw` or your preferred firewall to restrict access to management ports.
- Run services as non-root (`mm2` user) and keep binaries owned by root with
  read-only permissions.
- Use `systemd` `ProtectHome=yes`, `ProtectSystem=strict`, `NoNewPrivileges`
  if your distribution supports them.
- Store API keys in an environment file with `600` permissions and restrict sudo
  access.
- Keep Go toolchain and OS packages patched.

---

## 12. Troubleshooting

| Symptom | Action |
|---------|--------|
| Service stuck in restart loop | `journalctl -u prices-gleec-com` for stack traces; ensure API keys are present. |
| Missing coins/pairs | Re-run `enable COIN`; inspect `/opt/mm2-client/coins_config.json`. |
| Price endpoint stale | Check network connectivity to upstream providers, confirm cron updates succeeded. |
| CLI cannot connect to mm2 | Run `> start` again or restart underlying mm2 daemon; ensure ports 7783/1313 are free. |

---

For advanced configuration (custom price providers, alternative bot configs),
refer to `MarketMaking.md` and the source code under `cmd/mm2_tools_server`.

