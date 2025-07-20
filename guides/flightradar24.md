# Install Flightradar24 ADSB Feed on Raspberry Pi

This tutorial will guide you through manually installing the Flightradar24 ADSB feeder on a Raspberry Pi.

## Prerequisites

- Raspberry Pi running a Debian-based OS (Raspberry Pi OS recommended)
- ADSB receiver hardware (RTL-SDR dongle or similar)
- Obtained a sharing key from Flightradar24. [Get your sharing key here.](https://www.flightradar24.com/account/data-sharing)

## Installation Steps

### 1. Add the Flightradar24 repository

```sh
wget -O- https://repo-feed.flightradar24.com/flightradar24.pub | sudo gpg --dearmor | sudo tee /etc/apt/keyrings/flightradar24.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/flightradar24.gpg] https://repo-feed.flightradar24.com flightradar24 raspberrypi-stable" | sudo tee /etc/apt/sources.list.d/fr24feed.list
sudo apt update
```

### 3. Install Flightradar24 and dependencies

Ensure you have the necessary dependencies installed:

```sh
sudo apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" fr24feed lighttpd librtlsdr0 libusb-1.0-0 dump1090-mutability
```

### 3. Start the fr24feed service

You can start the fr24feed service in two ways: using dump1090-mutability or dump1090-fa.

#### 3.1. Using dump1090-mutability

If you're switching from dump1090-fa to dump1090-mutability, you need to disable dump1090-fa first:

```sh
sudo systemctl stop fr24feed
sudo systemctl stop lighttpd
sudo lighty-disable-mod skyaware
sudo systemctl disable --now dump1090-fa
```

Then, install the necessary dependencies and dump1090-mutability:

```sh
sudo apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" lighttpd librtlsdr0 libusb-1.0-0 dump1090-mutability
sudo ln -fs /usr/bin/dump1090-mutability /usr/lib/fr24/dump1090
sudo lighty-enable-mod dump1090
sudo systemctl enable --now lighttpd
```

```sh
export SHARING_KEY="your_sharing_key_here"
cat <<EOF | sudo tee /etc/fr24feed.ini > /dev/null
fr24key="$SHARING_KEY"
receiver="dvbt"
path="/usr/lib/fr24/dump1090"
bs="no"
raw="no"
logmode="1"
procargs="--gain -10 --net"
windowmode="0"
mpx="no"
mlat="yes"
mlat-without-gps="yes"
bind-interface="0.0.0.0"
EOF
```

#### 3.2. Using dump1090-fa

If you're switching from dump1090-mutability to dump1090-fa, you need to disable dump1090-mutability first:

```sh
sudo systemctl stop fr24feed
sudo systemctl stop lighttpd
sudo lighty-disable-mod dump1090
```

Then, install the necessary dependencies and dump1090-fa:

```sh
wget https://www.flightaware.com/adsb/piaware/files/packages/pool/piaware/f/flightaware-apt-repository/flightaware-apt-repository_1.1_all.deb
sudo dpkg -i flightaware-apt-repository_1.1_all.deb
sudo rm flightaware-apt-repository_1.1_all.deb
sudo apt update
sudo apt install -y dump1090-fa
sudo systemctl enable --now dump1090-fa
sudo systemctl enable --now lighttpd
```

Then configure fr24feed to use dump1090-fa:

```sh
export SHARING_KEY="your_sharing_key_here"
cat <<EOF | sudo tee /etc/fr24feed.ini > /dev/null
fr24key="$SHARING_KEY"
receiver="avr-tcp"
host="127.0.0.1:30002"
bs="no"
raw="no"
logmode="1"
procargs="--gain -10 --net"
windowmode="0"
mpx="no"
mlat="yes"
mlat-without-gps="yes"
bind-interface="0.0.0.0"
EOF
```

### 4. Start and Enable Service

After configuration, start and enable the service to run automatically:

```sh
sudo systemctl enable --now fr24feed
sudo systemctl restart fr24feed
```

### 5. Verify Installation

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
