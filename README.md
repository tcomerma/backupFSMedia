backupFSMedia
=============

Script per backup de fitxers via rsync amb snapshots via zfs

Objectiu:
Aquest script s'ha fet per poder fer backup d'un NAS que publica una gran
volum de fitxers (12 volums, amb >30T en total), pel que la solució de backup
tradicional no ens funcionava.

L'script s'executa en un servidor solaris 11 que munta per nfs els volums del NAS
i en fa backup amb rsync, generant després un snapshot de zfs. L'script controla el
número de snapshots que es volen guardar.

Notifica per correu i nagios el resultat.
-------------------------------------------------------------------------

Script to backup files via rsync and make snapshots with ZFS

Objective:
This script has been made to backup huge volumes published fron a NAS  
(12 volumes, with> 30T in total), so traditional backup solution didn't work.

The script runs on a Solaris 11 server that mounts NAS volumes using NFS
and made backup with rsync, afterwards creates a ZFS snapshot. The script controls
number of snapshots that you want to keep.

Email and Nagios notifies the result.