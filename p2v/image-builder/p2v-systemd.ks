mkdir /p2v

# Configure the machine to write compressed core files to /tmp
cat > /p2v/core.sh <<'EOF'
#!/bin/sh
/usr/bin/gzip -c > /tmp/$1.core.gz
EOF
chmod 755 /p2v/core.sh

cat > /p2v/run.sh <<'EOF'
#!/bin/sh

# Use /p2v/core.sh to handle core files
echo "|/p2v/core.sh %h-%e-%p-%t" > /proc/sys/kernel/core_pattern
ulimit -c unlimited

Xlog=/tmp/X.log
again=$(mktemp)

while [ -f "$again" ]; do
    if [[ $(cat /proc/cmdline) =~ "p2v_nogui=true" ]] ; then
      /usr/bin/openvt -sw -c 7 -f -- bash -c "
/usr/bin/virt-p2v-launcher -nogui 2>&1 | tee -a $Xlog
"
    else
      /usr/bin/xinit /usr/bin/virt-p2v-launcher > $Xlog 2>&1
    fi

    # virt-p2v-launcher will have touched this file if it ran
    if [ -f /tmp/virt-p2v-launcher ]; then
        rm $again
        break
    fi

    /usr/bin/openvt -sw -c 7 -f -- /bin/bash -c "
cat $Xlog
echo
echo virt-p2v-launcher failed
select c in \
    \"Try again\" \
    \"Debug\" \
    \"Power off\" \
    \"View log\"
do
    if [ \"\$c\" == Debug ]; then
        echo Output was written to $Xlog
        echo Any core files will have been written to /tmp
        echo Exit this shell to run virt-p2v-launcher again
        bash -l
    elif [ \"\$c\" == \"Power off\" ]; then
        rm $again
    elif [ \"\$c\" == \"View log\" ]; then
        TERM=xterm less /tmp/X.log
        continue
    fi
    break
done
"

done
/sbin/poweroff
EOF
chmod 755 /p2v/run.sh

# Start the P2V client during the (default) graphical boot
cat > /etc/systemd/system/p2v.service <<'EOF'
[Unit]
Description = P2V Client

[Service]
ExecStart=/p2v/run.sh
Requires=NetworkManager.service
After=NetworkManager.service

[Install]
WantedBy=graphical.target
EOF

systemctl load /etc/systemd/system/p2v.service
systemctl enable p2v.service

# Update the default getty target to login automatically as root without
# prompting for a password
sed -i 's/^ExecStart=\(.*\)/ExecStart=\1 -a root/' \
    /usr/lib/systemd/system/getty@.service

# Reserve tty1 as a getty so we can document it clearly
echo ReserveVT=1 >> /etc/systemd/logind.conf
