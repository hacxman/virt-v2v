#!/bin/bash -
# virt-v2v
# Copyright (C) 2009 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
# Rebuild the autotools environment.

set -e
set -v

# Run autopoint, to get po/Makevars.template:
autopoint

# Create gettext configuration.
echo "$0: Creating po/Makevars from po/Makevars.template ..."
rm -f po/Makevars
sed '
  /^EXTRA_LOCALE_CATEGORIES *=/s/=.*/= '"$EXTRA_LOCALE_CATEGORIES"'/
  /^MSGID_BUGS_ADDRESS *=/s/=.*/= '"$MSGID_BUGS_ADDRESS"'/
  /^XGETTEXT_OPTIONS *=/{
    s/$/ \\/
    a\
        '"$XGETTEXT_OPTIONS"' $${end_of_xgettext_options+}
  }
' po/Makevars.template >po/Makevars

autoreconf -i

CONFIGUREDIR=.

# Run configure in BUILDDIR if it's set
if [ ! -z "$BUILDDIR" ]; then
    mkdir -p $BUILDDIR
    cd $BUILDDIR

    CONFIGUREDIR=..
fi

# If no arguments were specified and configure has run before, use the previous
# arguments
if [ $# == 0 -a -x ./config.status ]; then
    ./config.status --recheck
else
    $CONFIGUREDIR/configure "$@"
fi
