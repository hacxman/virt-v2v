# Run virt-p2v
if [ ! -e /etc/rc.d/rc.local ]; then
    echo "#!/bin/sh" > /etc/rc.d/rc.local
    chmod 755 /etc/rc.d/rc.local
fi

cat >> /etc/rc.d/rc.local <<'EOF'

# Configure the machine to write compressed core files to /tmp
cat > /tmp/core.sh <<'CORE'
#!/bin/sh
/usr/bin/gzip -c > /tmp/$1.core.gz
CORE

chmod 755 /tmp/core.sh
echo "|/tmp/core.sh %h-%e-%p-%t" > /proc/sys/kernel/core_pattern
ulimit -c unlimited

Xlog=/tmp/X.log
again=$(mktemp)

# Launch a getty on tty2 to allow debugging while the program runs
/usr/bin/setsid mingetty --autologin root /dev/tty2 &
/usr/bin/chvt 1

while [ -f "$again" ]; do
    if [[ $(cat /proc/cmdline) =~ "p2v_nogui=true" ]] ; then
      /usr/bin/openvt -c 1 -f -- bash -c "
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

    /usr/bin/openvt -sw -- /bin/bash -c "
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
