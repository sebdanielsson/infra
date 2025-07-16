# Install FlightRadar24 ADSB Feed on Raspberry Pi

This tutorial will guide you through manually installing the FlightRadar24 ADSB feeder on a Raspberry Pi.

## Prerequisites

- Raspberry Pi running a Debian-based OS (Raspberry Pi OS recommended)
- ADSB receiver hardware (RTL-SDR dongle or similar)

## Installation Steps

### 1. Add the FlightRadar24 repository

```sh
wget -O- https://repo-feed.flightradar24.com/flightradar24.pub | sudo gpg --dearmor | sudo tee /etc/apt/keyrings/flightradar24.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/flightradar24.gpg] https://repo-feed.flightradar24.com flightradar24 raspberrypi-stable" | sudo tee /etc/apt/sources.list.d/fr24feed.list
sudo apt update
```

### 2. Install FlightRadar24 Feed Software

Update package lists and install the fr24feed package:

```sh
# sudo apt install -y dump1090-mutability
sudo apt install -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y fr24feed
```

### 3. Install Additional Dependencies

Ensure you have the necessary dependencies installed:

```sh
sudo apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" lighttpd librtlsdr0 libusb-1.0-0 dump1090-mutability
sudo ln -fs /usr/bin/dump1090-mutability /usr/lib/fr24/dump1090
sudo lighty-enable-mod dump1090 || true
sudo service lighttpd force-reload || true
sudo systemctl enable lighttpd || true
sudo systemctl start lighttpd || true
```

### 4. Start the fr24feed service

#### 4.1 Option 1: Start using existing sharing key

```sh
sudo systemctl stop fr24feed || true
sudo systemctl stop fr24uat-feed || true
```

```sh
export SHARING_KEY="your_sharing_key_here"
cat <<EOF | sudo tee /etc/fr24feed.ini > /dev/null
receiver="dvbt"
fr24key="$SHARING_KEY"
bs="no"
raw="no"
path="/usr/lib/fr24/dump1090"
logmode="1"
procargs="--gain -10 --net"
windowmode="0"
mpx="no"
mlat="yes"
mlat-without-gps="yes"
bind-interface="0.0.0.0"
EOF
```

### 4.2 Option 2: Start without sharing key

Run the ADSB signup wizard to configure your feeder:

```sh
sudo fr24feed-signup-adsb
```

During the signup process, you'll be prompted to:

- Enter your email address
- Provide your sharing key (if you have one) or create a new account
- Configure your receiver settings (antenna location, receiver type, etc.)
- Set data sharing preferences

### 5. Start and Enable Service

After configuration, start and enable the service to run automatically:

```sh
sudo systemctl start fr24feed
sudo systemctl enable fr24feed
```

### 6. Verify Installation

Check that the service is running properly:

```sh
sudo systemctl status fr24feed
```

You can also check the logs for any issues:

```bash
sudo journalctl -u fr24feed -f
```

## Accessing the Web Interface

### Flightradar24

The Flightradar24 feeder web interface can accessed at: <http://flightradar:8754>.

### dump1090

The dump1090 web interface, which provides a live map of aircraft, can be accessed at: <http://flightradar/dump1090>

## Potential Issues

### Wifi on Raspberry Pi

If you plan on using wifi on your Raspberry Pi *NetworkManager* might enable rfkill (check with `rfkill list`). To get network connectivity back you need to enable wifi through NetworkManager.

Check status and available networks:

```sh
nmcli device status
nmcli dev wifi list
```

Connect to your WiFi network:

```sh
nmcli dev wifi connect Hogwarts password Horcrux10 ifname wlan0
```

Check status and connected networks to confirm:

```sh
nmcli device status
nmcli dev wifi list
```
