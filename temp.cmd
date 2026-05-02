wsl -d GentooHA -- bash -c "systemd-machine-id-setup || true; dbus-uuidgen --ensure=/etc/machine-id; [ -e /var/lib/dbus/machine-id ] || ln -s /etc/machine-id /var/lib/dbus/machine-id; systemctl disable --now systemd-firstboot.service || true; systemctl mask systemd-firstboot.service || true; systemctl daemon-reload"
wsl --shutdown
wsl -d GentooHA -- systemctl is-system-running
wsl -d GentooHA -- systemctl start docker
wsl -d GentooHA -- systemctl status docker --no-pager -l