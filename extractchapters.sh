#!/usr/bin/env bash
for f in *.mkv
do
 echo -n $f  ' '
 /usr/local/Cellar/mkvtoolnix/80.0/bin/mkvextract "$f" chapters "$f.xml"
done
