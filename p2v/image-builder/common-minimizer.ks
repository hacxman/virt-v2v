# This file is only relatively lightly modified from the version copied from
# oVirt, and certainly contains much which is irrelevant to this image. I have,
# however, removed some obviously extraneous entries and added a few additional
# entries.
#
# Matthew Booth <mbooth@redhat.com> - 18/4/2011

%post --nochroot --interpreter image-minimizer
# lokkit is just an install-time dependency; we can remove
# it afterwards, which we do here
droprpm system-config-*
droprpm libsemanage-python
droprpm python-libs
droprpm python

droprpm mkinitrd
droprpm isomd5sum
droprpm dmraid
droprpm checkpolicy
droprpm make
droprpm policycoreutils-python
droprpm setools-libs-python
droprpm setools-libs

droprpm gamin
droprpm pm-utils
droprpm kbd
droprpm usermode
droprpm vbetool
droprpm ConsoleKit
droprpm hdparm
droprpm efibootmgr
droprpm linux-atm-libs
droprpm mtools
droprpm syslinux
droprpm wireless-tools
droprpm radeontool
droprpm libicu
droprpm gnupg2
droprpm fedora-release-notes
droprpm fedora-logos

# cronie pulls in exim (sendmail) which pulls in all kinds of perl deps
droprpm exim
droprpm perl*
droprpm postfix
droprpm mysql*

droprpm sysklogd

# unneeded rhn deps
droprpm yum*

# pam complains when this is missing
keeprpm ConsoleKit-libs

# kernel modules minimization

# filesystems
drop /lib/modules/*/kernel/fs
keep /lib/modules/*/kernel/fs/ext*
keep /lib/modules/*/kernel/fs/jbd*
keep /lib/modules/*/kernel/fs/btrfs
keep /lib/modules/*/kernel/fs/fat
keep /lib/modules/*/kernel/fs/nfs
keep /lib/modules/*/kernel/fs/nfs_common
keep /lib/modules/*/kernel/fs/fscache
keep /lib/modules/*/kernel/fs/lockd
keep /lib/modules/*/kernel/fs/nls/nls_utf8.ko
# autofs4     configfs  exportfs *fat     *jbd    mbcache.ko  nls       xfs
#*btrfs       cramfs   *ext2     *fscache *jbd2  *nfs         squashfs
# cachefiles  dlm      *ext3      fuse     jffs2 *nfs_common  ubifs
# cifs        ecryptfs *ext4      gfs2    *lockd  nfsd        udf

# network
drop /lib/modules/*/kernel/net
keep /lib/modules/*/kernel/net/802*
keep /lib/modules/*/kernel/net/bridge
keep /lib/modules/*/kernel/net/core
keep /lib/modules/*/kernel/net/ipv*
keep /lib/modules/*/kernel/net/key
keep /lib/modules/*/kernel/net/llc
keep /lib/modules/*/kernel/net/netfilter
keep /lib/modules/*/kernel/net/rds
keep /lib/modules/*/kernel/net/sctp
keep /lib/modules/*/kernel/net/sunrpc
#*802    atm        can   ieee802154 *key      *netfilter  rfkill *sunrpc  xfrm
#*8021q  bluetooth *core *ipv4       *llc       phonet     sched   wimax
# 9p    *bridge     dccp *ipv6        mac80211 *rds       *sctp    wireless

drop /lib/modules/*/kernel/sound

# drivers
drop /lib/modules/*/kernel/drivers
keep /lib/modules/*/kernel/drivers/ata
keep /lib/modules/*/kernel/drivers/block
keep /lib/modules/*/kernel/drivers/cdrom
keep /lib/modules/*/kernel/drivers/char
keep /lib/modules/*/kernel/drivers/cpufreq
keep /lib/modules/*/kernel/drivers/dca
keep /lib/modules/*/kernel/drivers/dma
keep /lib/modules/*/kernel/drivers/edac
keep /lib/modules/*/kernel/drivers/firmware
keep /lib/modules/*/kernel/drivers/idle
keep /lib/modules/*/kernel/drivers/infiniband
keep /lib/modules/*/kernel/drivers/md
keep /lib/modules/*/kernel/drivers/message
keep /lib/modules/*/kernel/drivers/net
drop /lib/modules/*/kernel/drivers/net/pcmcia
drop /lib/modules/*/kernel/drivers/net/wireless
drop /lib/modules/*/kernel/drivers/net/ppp*
keep /lib/modules/*/kernel/drivers/pci
keep /lib/modules/*/kernel/drivers/scsi
keep /lib/modules/*/kernel/drivers/staging/ramzswap
keep /lib/modules/*/kernel/drivers/uio
keep /lib/modules/*/kernel/drivers/usb
drop /lib/modules/*/kernel/drivers/usb/atm
drop /lib/modules/*/kernel/drivers/usb/class
drop /lib/modules/*/kernel/drivers/usb/image
drop /lib/modules/*/kernel/drivers/usb/misc
drop /lib/modules/*/kernel/drivers/usb/serial
keep /lib/modules/*/kernel/drivers/vhost
keep /lib/modules/*/kernel/drivers/virtio

# acpi       *cpufreq   hid         leds      mtd      ?regulator  uwb
#*ata         crypto   ?hwmon      *md       *net*      rtc       *vhost
# atm        *dca      ?i2c         media    ?parport  *scsi*      video
# auxdisplay *dma      *idle        memstick *pci      ?serial    *virtio
#*block      *edac      ieee802154 *message   pcmcia   ?ssb        watchdog
# bluetooth   firewire *infiniband ?mfd       platform *staging    xen
#*cdrom      *firmware  input       misc     ?power    ?uio
#*char*      ?gpu       isdn        mmc      ?pps      *usb

drop /usr/share/zoneinfo
keep /usr/share/zoneinfo/UTC

drop /etc/alsa
drop /usr/share/alsa
drop /usr/share/awk
drop /usr/share/anaconda
drop /usr/share/backgrounds
drop /usr/share/wallpapers
drop /usr/share/kde-settings
drop /usr/share/gnome-background-properties
drop /usr/share/dracut
drop /usr/share/plymouth
drop /usr/share/setuptool
drop /usr/share/hwdata/MonitorsDB
drop /usr/share/hwdata/oui.txt
drop /usr/share/hwdata/videoaliases
drop /usr/share/hwdata/videodrivers
drop /usr/share/firstboot
drop /usr/share/lua
drop /usr/share/kde4
drop /usr/share/pixmaps
drop /usr/share/icons
drop /usr/share/fedora-release
drop /usr/share/tabset

drop /usr/share/tc
drop /usr/share/emacs
drop /usr/share/info
drop /usr/src
drop /usr/etc
drop /usr/games
drop /usr/include
drop /usr/local
drop /usr/sbin/dell*
keep /usr/sbin/build-locale-archive
drop /usr/sbin/glibc_post_upgrade.*
drop /usr/lib*/tc
drop /usr/lib*/tls
drop /usr/lib*/sse2
drop /usr/lib*/pkgconfig
drop /usr/lib*/nss
drop /usr/lib*/games
drop /usr/lib*/alsa-lib
drop /usr/lib*/krb5
drop /usr/lib*/hal
drop /usr/lib*/gio

# syslinux
drop /usr/share/syslinux
# glibc-common locales
drop /usr/lib/locale
keep /usr/lib/locale/usr/share/locale/en_US
# openssh
drop /usr/bin/sftp
drop /usr/bin/slogin
drop /usr/bin/ssh-add
drop /usr/bin/ssh-agent
drop /usr/bin/ssh-keyscan
# docs
drop /usr/share/omf
drop /usr/share/gnome
drop /usr/share/doc
keep /usr/share/doc/*-firmware-*
drop /usr/share/locale/
keep /usr/share/locale/en_US
drop /usr/share/man
drop /usr/share/i18n
drop /boot/*
drop /var/lib/builder

drop /usr/lib*/libboost*
keep /usr/lib*/libboost_program_options.so*
keep /usr/lib*/libboost_filesystem.so*
keep /usr/lib*/libboost_thread-mt.so*
keep /usr/lib*/libboost_system.so*
drop /usr/kerberos
keep /usr/kerberos/bin/kinit
keep /usr/kerberos/bin/klist
drop /lib/firmware
keep /lib/firmware/3com
keep /lib/firmware/acenic
keep /lib/firmware/adaptec
keep /lib/firmware/advansys
keep /lib/firmware/bnx2
keep /lib/firmware/cxgb3
keep /lib/firmware/e100
keep /lib/firmware/myricom
keep /lib/firmware/ql*
keep /lib/firmware/sun
keep /lib/firmware/tehuti
keep /lib/firmware/tigon
drop /lib/kbd/consolefonts
drop /etc/pki/tls
drop /etc/pki/java
drop /etc/pki/nssdb
drop /etc/pki/rpm-gpg
%end

%post
echo "Removing python source files"
find / -name '*.py' -exec rm -f {} \;
find / -name '*.pyo' -exec rm -f {} \;

%end
