# Installing Budgie as a Systemd Service

To run Budgie as a background service that auto-starts on boot:

## Installation

1. Copy the service file to systemd:
```bash
sudo cp budgie.service /etc/systemd/system/budgie.service
```

2. Reload systemd to recognize the new service:
```bash
sudo systemctl daemon-reload
```

3. Enable the service to start on boot:
```bash
sudo systemctl enable budgie
```

4. Start the service:
```bash
sudo systemctl start budgie
```

## Managing the Service

Check status:
```bash
sudo systemctl status budgie
```

View logs:
```bash
sudo journalctl -u budgie -f
```

Restart:
```bash
sudo systemctl restart budgie
```

Stop:
```bash
sudo systemctl stop budgie
```

## Configuration

The service uses the default settings from `bin/budgie-server`. To customize, set environment variables in the service file or edit the line:

```
Environment="BUDGIE_PORT=4567"
Environment="BUDGIE_HOST=0.0.0.0"
```

Then reload and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart budgie
```

## Troubleshooting

If the service won't start, check the logs:
```bash
sudo journalctl -u budgie -n 50
```

Make sure the database path is readable/writable by the `daniel` user:
```bash
ls -la /home/daniel/budgie.data/
```
