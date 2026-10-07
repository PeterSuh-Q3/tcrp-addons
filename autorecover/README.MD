The main function of this ADDON is to cover the manual POSTUPDATE of TCRP REDPILL. 

Detects changes in smanllfixversion between DSM versions, and when changes occur, 
automatically patches the ramdisk of /dev/md0 to the synoboot2 partition to replace postupdate processing.

On `rcExit`, if the effective GRUB default is DSM reinstall entry 3, the addon resets both `grub.cfg` and `grubenv` to entry 0 so a later reboot returns to the normal loader entry. This check is independent of the smallfix recovery path and does not rely on JOT-specific conditions.
