#!/usr/bin/env bash
# Installs rpi-power-monitor (aXon fork, MQTT-only, no InfluxDB) on Raspberry Pi OS Bookworm.
# Usage on the Pi:  bash ~/rpi-power-monitor/install-powerpi.sh
set -euo pipefail

REPO_DIR="$HOME/rpi-power-monitor"
VENV="$HOME/pm-venv"
APP_DIR="$REPO_DIR/rpi_power_monitor"
CONFIG="$APP_DIR/config.toml"

echo "== 1/5 SPI einschalten"
sudo raspi-config nonint do_spi 0

echo "== 2/5 Systempakete"
sudo apt-get install -y git python3-venv python3-dev build-essential

echo "== 3/5 Python-Umgebung"
[ -d "$VENV" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip wheel
"$VENV/bin/pip" install -r "$REPO_DIR/requirements.txt" "paho-mqtt>=2"

echo "== 4/5 Konfiguration"
if [ ! -f "$CONFIG" ]; then
    cp "$APP_DIR/config.example.toml" "$CONFIG"
    read -rp "MQTT-Benutzer [powerpi]: " MQTT_USER; MQTT_USER=${MQTT_USER:-powerpi}
    read -rsp "MQTT-Passwort: " MQTT_PASS; echo
    sed -i "s|username = \"powerpi\" .*|username = \"$MQTT_USER\"|; s|password = \"ANPASSEN\"|password = \"$MQTT_PASS\"|" "$CONFIG"
    chmod 600 "$CONFIG"
    echo "   $CONFIG angelegt."
else
    echo "   $CONFIG existiert bereits, bleibt unverändert."
fi

echo "== 5/5 Dienst einrichten"
sudo tee /etc/systemd/system/power-monitor.service >/dev/null <<EOF
[Unit]
Description=Raspberry Pi Power Monitor
After=network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$VENV/bin/python $APP_DIR/power_monitor.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable power-monitor

if [ ! -e /dev/spidev0.0 ]; then
    echo
    echo "SPI wird erst nach einem Neustart aktiv:  sudo reboot"
    echo "Danach startet der Dienst automatisch."
else
    sudo systemctl restart power-monitor
    sleep 5
    systemctl status power-monitor --no-pager | head -12
fi

echo
echo "Kanäle live prüfen (Dienst vorher stoppen):"
echo "  sudo systemctl stop power-monitor"
echo "  cd $APP_DIR && $VENV/bin/python power_monitor.py --mode terminal"
echo "  (Strg+C beendet, danach: sudo systemctl start power-monitor)"
