#!/bin/bash

FOLDER="/home/admin/mm2-client"
rm ${FOLDER}/coins
wget -P ${FOLDER} https://raw.githubusercontent.com/KomodoPlatform/coins/master/coins

# Use this as a daily cron job

cd ${FOLDER}/mm2_tools_server
# backup existing coins_config.json
cp ${FOLDER}/coins_config.json ${FOLDER}/coins_config.json.bk
# Get new coins_config.json from source
/usr/bin/curl https://raw.githubusercontent.com/KomodoPlatform/coins/master/utils/coins_config.json -o ${FOLDER}/coins_config.json
# Check new coins_config.json file is valid
data=$(cat ${FOLDER}/coins_config.json | wc -l)
# Revert to old file if new file is invalid
if [[ "$data" -eq 1 ]]; then
    ${FOLDER}/coins_config.json.bk ${FOLDER}/coins_config.json
fi
# Rebuild service
/usr/local/go/bin/go build -o ${FOLDER}/prices_komodo_earth ${FOLDER}/cmd/mm2_tools_server/mm2_tools_server.go
# restart service
/bin/systemctl restart prices-komodo-earth
# Print date for logs
now=$(date +%m-%d-%Y)
echo "prices updated at ${now}"
