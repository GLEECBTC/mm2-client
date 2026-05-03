# mm2-client

Custom mm2 (AtomicDEX) tooling that bundles:

- an interactive CLI to drive local mm2 nodes,
- a reusable HTTP server that can start/stop market maker bots, and
- a price aggregation service that feeds on Binance, Coingecko, CoinPaprika, etc.

Use it to bootstrap simple market-making strategies, integrate the server into
desktop or mobile apps, or operate a standalone price oracle.

---

## Roadmap / Future Tasks

- [ ] Wallet + encryption seed
- [ ] cancel_all_order
- [x] setprice
- [ ] buy
- [ ] sell
- [x] my_recent_swaps
- [x] my_orders
- [x] prompt use DB desktop
- [x] cancel (UUID support)
- [x] update_maker_order (track UUID)
- [x] gecko price service
- [x] paprika price service
- [x] binance websocket service
- [x] add total in my_balance_all
- [x] add am_i_seed in `MM2.json`
- [x] get_binance_supported_pairs
- [x] start mm2 without extra services
- [x] generic price service (Binance, Gecko, Paprika)
- [x] simple bot cfg template

---

## Local Quick Start (Linux)

```bash
wget https://golang.org/dl/go1.16.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.16.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
git clone https://github.com/Milerius/mm2-client
cd mm2-client && go build cmd/mm2_cli_native/mm2_client.go
mkdir -p mm2
cp assets/simple_market_bot.template.json mm2/simple_market_bot.json
# edit the cfg if you want and remove the commentary
./mm2_client

> help
> init                      # run once to bootstrap mm2
> start
> enable_active_coins
> enable COIN_A COIN_B      # enable individual coins if still inactive
> get_binance_supported_pairs COIN_A

# Fund balances before starting the bot
> start_simple_market_maker_bot
> my_orders

# later
> stop_simple_market_maker_bot
> stop
> exit

## from another terminal
tail -f ~/.atomicdex_cli/logs/mm2.client.log
```

---

## Simple Market Maker over an Existing AtomicDEX Daemon

```bash
go build -o mm2_tools_server_bin cmd/mm2_tools_server/mm2_tools_server.go
./mm2_tools_server_bin

# Assuming your userpass for the session is foobar
# Starting the simple market maker bot
curl --location --request POST 'localhost:13579/api/v1/start_simple_market_maker_bot' \
--header 'Content-Type: application/json' \
--data-raw '{
  "desktop_cfg_path": "/Users/milerius/coins/utils/coins_config.json",
  "mm2_coins_cfg_path": "/Users/milerius/Library/Application Support/AtomicDex Desktop/0.5.0/configs/coins.json",
  "market_maker_cfg_path": "/Users/milerius/GolandProjects/mm2-client/mm2/simple_market_bot.json",
  "mm2_userpass": "foobar"
}'

# stopping the bot
curl --location --request POST 'localhost:13579/api/v1/stop_simple_market_maker_bot'
```

---

## Mobile Bindings

### iOS

Build the framework:

```bash
cd mm2_tools_server
gomobile bind -v --target=ios .
```

Use it in Objective-C:

```obj-c
#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Mm2_tools_server.h"

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        Mm2_tools_serverLaunchServer(@"atomic_dex");
    });
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
```

### Android

Generate the AAR:

```bash
cd mm2_tools_server
gomobile bind -v --target=android .
```

Consume it from Kotlin:

```kt
import mm2_tools_server.Mm2_tools_server
import kotlin.concurrent.thread

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val navView: BottomNavigationView = binding.navView
        val navController = findNavController(R.id.nav_host_fragment_activity_main)
        val appBarConfiguration = AppBarConfiguration(
            setOf(
                R.id.navigation_home, R.id.navigation_dashboard, R.id.navigation_notifications
            )
        )

        thread { Mm2_tools_server.launchServer("atomicDex") }
        setupActionBarWithNavController(navController, appBarConfiguration)
        navView.setupWithNavController(navController)
    }
}
```

Misc:

```
# for Android emulators you can forward the local port:
adb forward tcp:1313 tcp:1313
```

---

## API Keys & Environment

API keys used by `constants/constants.go` feed the price service. Export them
before launching the server or include them via systemd `EnvironmentFile`.

```
LCW_API_KEY=
GECKO_API_KEY=
PAPRIKA_API_KEY=
```

---

## Build Only the Price Service

```bash
go build -o mm2_tools_server_bin cmd/mm2_tools_server/mm2_tools_server.go
./mm2_tools_server_bin
```

Set `-only_price_service=true` to disable the CLI features.

---

## Example Systemd Service

```ini
[Unit]
Description=prices-gleec-com
After=multi-user.target
Conflicts=getty@tty1.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Environment="LCW_API_KEY=<YOUR_LCW_API_KEY>"
WorkingDirectory=/home/tech/mm2-client
ExecStart=/home/tech/mm2-client/mm2_tools_server_bin -only_price_service=true
StandardOutput=append:/home/tech/logs/prices-gleec-com.log
StandardError=append:/home/tech/logs/prices-gleec-com.log
User=admin
Group=admin
Type=simple
TimeoutStopSec=30min
Restart=on-failure
RestartSec=10s
StandardInput=tty-force

[Install]
WantedBy=multi-user.target
```

For a hardened, end-to-end deployment checklist see
`docs/production-deployment.md`.

---

## Automating Coins Updates

Run the provided script daily (root cron) to fetch the upstream coins list,
rebuild the price service binary, and restart the daemon.

```bash
#!/bin/bash
curl https://raw.githubusercontent.com/GLEECBTC/coins/master/utils/coins_config.json -o /home/tech/mm2-client/coins_config.json
go build -o /home/tech/mm2-client/mm2_tools_server_bin /home/tech/mm2-client/cmd/mm2_tools_server/mm2_tools_server.go
systemctl restart prices-gleec-com
```

Adjust paths and add logging to taste.

---

## Additional Documentation

- `MarketMaking.md` – detailed explanation of the market maker configuration.
- `docs/production-deployment.md` – full production deployment guide (systemd,
  cron, backups, hardening).

