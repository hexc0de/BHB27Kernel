# AnyKernel2 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
# EDIFY properties
kernel.string=BHB27-Kernel by BHB27 @ xda-developers
do.devicecheck=0
do.initd=0
do.modules=1
do.cleanup=1
do.buildprop=1
device.name1=quark

zramsize=1; 
# to change the above value use a value in MB times 1024 times 1024 or MB_value x 1024 x 1024
# eg 500MB is 500 x 1024 x 1024 = 524288000
# so zramsize=524288000;
# use zramsize=0; to disable the featuring

# shell variables
docmdline=1;
is_slot_device=0;
romtype=0;
sdk=24;
## end setup

## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
if [ "$romtype" == 0 ]; then
	ramdisk=/tmp/anykernel/ramdisk/custom;
	patch=/tmp/anykernel/patch/custom;
elif [ "$romtype" == 1 ]; then
	ramdisk=/tmp/anykernel/ramdisk/mcustom;
	patch=/tmp/anykernel/patch/mcustom;
elif [ "$romtype" == 2 ]; then
	ramdisk=/tmp/anykernel/ramdisk/stock;
	patch=/tmp/anykernel/patch/stock;
fi
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img;

if [ "$is_slot_device" == 1 ]; then
  slot=$(getprop ro.boot.slot_suffix 2>/dev/null);
  test ! "$slot" && slot=$(grep -o 'androidboot.slot_suffix=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
  test "$slot" && block=$block$slot;
  if [ $? != 0 -o ! -e "$block" ]; then
    ui_print " "; ui_print "Unable to determine active boot slot. Aborting..."; exit 1;
  fi;
fi;

OUTFD=/proc/self/fd/$1;

# ui_print <text>
ui_print() { echo -e "ui_print $1\nui_print" > $OUTFD; }

# contains <string> <substring>
contains() { test "${1#*$2}" != "$1" && return 0 || return 1; }

# dump boot and extract ramdisk
dump_boot() {

  if [ -z "$block" ]; then
    for PARTITION in kern-a KERN-A android_boot ANDROID_BOOT kernel KERNEL boot BOOT lnx LNX; do
      block=$(readlink /dev/block/by-name/$PARTITION || readlink /dev/block/platform/*/by-name/$PARTITION || readlink /dev/block/platform/*/*/by-name/$PARTITION)
      if [ ! -z "$block" ]; then break; fi
    done
  fi;

  if [ -f "$bin/nanddump" ]; then
    $bin/nanddump -f /tmp/anykernel/boot.img $block;
  else
    dd if=$block of=/tmp/anykernel/boot.img;
  fi;
  if [ -f "$bin/unpackelf" ]; then
    $bin/unpackelf -i /tmp/anykernel/boot.img -o $split_img;
    mv -f $split_img/boot.img-ramdisk.cpio.gz $split_img/boot.img-ramdisk.gz;
  else
    $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  fi;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Dumping/splitting image failed. Aborting..."; exit 1;
  fi;
  if [ -f "$bin/mkmtkhdr" ]; then
    dd bs=512 skip=1 conv=notrunc if=$split_img/boot.img-ramdisk.gz of=$split_img/temprd;
    mv -f $split_img/temprd $split_img/boot.img-ramdisk.gz;
  fi;
  if [ -f "$bin/unpackelf" -a -f "$split_img/boot.img-dtb" ]; then
    case $(od -ta -An -N4 $split_img/boot.img-dtb | sed -e 's/del //' -e 's/   //g') in
      QCDT|ELF) ;;
      *) gzip $split_img/boot.img-zImage;
         mv -f $split_img/boot.img-zImage.gz $split_img/boot.img-zImage;
         cat $split_img/boot.img-dtb >> $split_img/boot.img-zImage;
         rm -f $split_img/boot.img-dtb;;
    esac;
  fi;
  mv -f $ramdisk /tmp/anykernel/rdtmp;
  mkdir -p $ramdisk;
  chmod 755 $ramdisk;
  magicbytes=$(hexdump -vn2 -e '2/1 "%x"' $split_img/boot.img-ramdisk.gz);
  lzma=0;
  contains $magicbytes "5d0" && lzma=1;
  cd $ramdisk;
  if [ "$lzma" == "1" ]; then
    lzma -dc $split_img/boot.img-ramdisk.gz | cpio -i;
  else
    gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i -d;
  fi;
  if [ $? != 0 -o -z "$(ls $ramdisk)" ]; then
    ui_print " "; ui_print "Unpacking ramdisk failed. Aborting..."; exit 1;
  fi;
  cp -af /tmp/anykernel/rdtmp/* $ramdisk;
}

# repack ramdisk then build and write image
write_boot() {
  cd $split_img;
  # Here I set the cmdline, selinux to permissive so I can boot and run my .sh with no problems
  # I also do some safety net related those help me to pass the verification running CM base ROM
  if [ $docmdline == 1 ]; then
    sed -ri 's/ androidboot.flash.locked=[0-1]//g' boot.img-cmdline
    sed -ri 's/ androidboot.bl_state=[0-2]//g' boot.img-cmdline
    sed -ri 's/ androidboot.verifiedbootstate=green|androidboot.verifiedbootstate=yellow|androidboot.verifiedbootstate=orange|androidboot.verifiedbootstate=red//g' boot.img-cmdline
    sed -ri 's/ buildvariant=eng|buildvariant=user|buildvariant=userdebug//g' boot.img-cmdline
    echo $(cat boot.img-cmdline) buildvariant=user androidboot.verifiedbootstate=green androidboot.bl_state=0 androidboot.flash.locked=1 > boot.img-cmdline
  fi;
  if [ -f *-cmdline ]; then
    cmdline=`cat *-cmdline`;
  fi;
  if [ -f *-board ]; then
    board=`cat *-board`;
  fi;
  base=`cat *-base`;
  pagesize=`cat *-pagesize`;
  kerneloff=`cat *-kerneloff`;
  ramdiskoff=`cat *-ramdiskoff`;
  if [ -f *-tagsoff ]; then
    tagsoff=`cat *-tagsoff`;
  fi;
  if [ -f *-osversion ]; then
    osver=`cat *-osversion`;
  fi;
  if [ -f *-oslevel ]; then
    oslvl=`cat *-oslevel`;
  fi;
  if [ -f *-second ]; then
    second=`ls *-second`;
    second="--second $split_img/$second";
    secondoff=`cat *-secondoff`;
    secondoff="--second_offset $secondoff";
  fi;
  for i in zImage zImage-dtb Image.gz Image.gz-dtb; do
    if [ -f /tmp/anykernel/$i ]; then
      kernel=/tmp/anykernel/$i;
      break;
    fi;
  done;
  if [ ! "$kernel" ]; then
    kernel=`ls *-zImage`;
    kernel=$split_img/$kernel;
  fi;
  if [ -f /tmp/anykernel/dtb ]; then
    dtb="--dt /tmp/anykernel/dtb";
  elif [ -f *-dtb ]; then
    dtb=`ls *-dtb`;
    dtb="--dt $split_img/$dtb";
  fi;
  if [ -f "$bin/mkbootfs" ]; then
    $bin/mkbootfs /tmp/anykernel/ramdisk | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  else
    cd $ramdisk;
#    if [ "$lzma" == "1" ]; then
#      find . | cpio -H newc -o | xz or lzma > /tmp/anykernel/ramdisk-new.cpio.lzma;
#    else
      find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
#    fi;
  fi;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Repacking ramdisk failed. Aborting..."; exit 1;
  fi;
  if [ -f "$bin/mkmtkhdr" ]; then
    cd /tmp/anykernel;
    $bin/mkmtkhdr --rootfs ramdisk-new.cpio.gz;
    mv -f ramdisk-new.cpio.gz-mtk ramdisk-new.cpio.gz;
    case $kernel in
      $split_img/*) ;;
      *) $bin/mkmtkhdr --kernel $kernel; kernel=$kernel-mtk;;
    esac;
  fi;
  $bin/mkbootimg --kernel $kernel --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset "$tagsoff" --os_version "$osver" --os_patch_level "$oslvl" $dtb --output /tmp/anykernel/boot-new.img;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Repacking image failed. Aborting..."; exit 1;
  elif [ `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
    ui_print " "; ui_print "New image larger than boot partition. Aborting..."; exit 1;
  fi;
  if [ -f "/data/custom_boot_image_patch.sh" ]; then
    ash /data/custom_boot_image_patch.sh /tmp/anykernel/boot-new.img;
    if [ $? != 0 ]; then
      ui_print " "; ui_print "User script execution failed. Aborting..."; exit 1;
    fi;
  fi;
  if [ -f "$bin/flash_erase" -a -f "$bin/nandwrite" ]; then
    $bin/flash_erase $block 0 0;
    $bin/nandwrite -p $block /tmp/anykernel/boot-new.img;
  else
    dd if=/dev/zero of=$block;
    dd if=/tmp/anykernel/boot-new.img of=$block;
  fi;
}

# backup_file <file>
backup_file() { test ! -f $1~ && cp $1 $1~; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# replace_section <file> <begin search string> <end search string> <replacement string>
replace_section() {
  begin=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
  for end in `grep -n "$3" $1 | cut -d: -f1`; do
    if [ "$begin" -lt "$end" ]; then
      if [ "$3" == " " ]; then
        sed -i "/${2//\//\\/}/,/^\s*$/d" $1;
      else
        sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
      fi;
      sed -i "${begin}s;^;${4}\n;" $1;
      break;
    fi;
  done;
}

# remove_section <file> <begin search string> <end search string>
remove_section() {
  begin=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
  for end in `grep -n "$3" $1 | cut -d: -f1`; do
    if [ "$begin" -lt "$end" ]; then
      if [ "$3" == " " ]; then
        sed -i "/${2//\//\\/}/,/^\s*$/d" $1;
      else
        sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
      fi;
      break;
    fi;
  done;
}

# insert_line <file> <if search string> <before|after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;${5}\n;" $1;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}d" $1;
  fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo "$(cat $patch/$3 $1)" > $1;
  fi;
}

# insert_file <file> <if search string> <before|after> <line match string> <patch file>
insert_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;\n;" $1;
    sed -i "$((line - 1))r $patch/$5" $1;
  fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo -ne "\n" >> $1;
    cat $patch/$3 >> $1;
    echo -ne "\n" >> $1;
  fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
  cp -pf $patch/$3 $1;
  chmod $2 $1;
}


# remove_file <file> <folder> leave folder empyt if file on root
remove_file() {
  if [ ! "$2" ]; then
    rm -rf $1;
  else
    rm -rf $2/$1;
  fi;
}

# patch_fstab <fstab file> <mount match name> <fs match type> <block|mount|fstype|options|flags> <original string> <replacement string>
patch_fstab() {
  entry=$(grep "$2" $1 | grep "$3");
  if [ -z "$(echo "$entry" | grep "$6")" ]; then
    case $4 in
      block) part=$(echo "$entry" | awk '{ print $1 }');;
      mount) part=$(echo "$entry" | awk '{ print $2 }');;
      fstype) part=$(echo "$entry" | awk '{ print $3 }');;
      options) part=$(echo "$entry" | awk '{ print $4 }');;
      flags) part=$(echo "$entry" | awk '{ print $5 }');;
    esac;
    newpart=$(echo "$part" | sed "s;${5};${6};");
    newentry=$(echo "$entry" | sed "s;${part};${newpart};");
    sed -i "s;${entry};${newentry};" $1;
  fi;
}

# check readme example tools arm only
seinject() {
  if [ "$sdk" -lt 24 ]; then
    $bin/sepolicy-inject $1 $ramdisk/sepolicy;
  else
    $bin/sepolicy-inject-N $1 $ramdisk/sepolicy;
  fi;
}

## end methods

## AnyKernel permissions
# set permissions for included files
chmod -R 755 $ramdisk

## AnyKernel install
dump_boot;

# begin ramdisk changes

if [ "$romtype" == 0 ]; then
	#Custom Nougat
	replace_string init.recovery.qcom.rc "interactive" "ondemand" "interactive"
	insert_line init.qcom.rc "/sys/module/state_notifier/parameters/enabled 1" after "on property:sys.boot_completed=1" "    write /sys/module/state_notifier/parameters/enabled 1"
elif [ "$romtype" == 1 ]; then
	#Custom Marshmallow
	replace_string init.recovery.qcom.rc "interactive" "ondemand" "interactive"
	replace_file init.qcom.power.rc 0750 init.qcom.power.rc
	replace_file init.qcom.rc 0750 init.qcom.rc
	replace_file fstab.qcom 0640 fstab.qcom
elif [ "$romtype" == 2 ]; then
	#Stock Marshmallow
	replace_string init.target.rc  "min_cores=4" "min_cores=1" "min_cores=4"
	insert_line init.qcom.rc "init.qcom.power.rc" after "import init.target.rc" "import init.qcom.power.rc"
	replace_line fstab.qcom "/dev/block/zram0" "/dev/block/zram0                                    none             swap             defaults                 zramsize=25%,swapprio=10"
fi

if [ "$zramsize" != 1 ]; then
	if [ "$romtype" == 2 ]; then
		replace_line fstab.qcom "/dev/block/zram0" "/dev/block/zram0                                    none             swap             defaults                 zramsize=$zramsize,swapprio=10"
	else
		replace_line fstab.qcom "/dev/block/zram0" "/dev/block/zram0                                    none             swap             defaults                 zramsize=$zramsize,swapprio=10,notrim"
	fi
fi

remove_line "sbin/post_init_rr.sh" "mount -o ro,remount /system;"
remove_line "sbin/restart.sh" "mount -o ro,remount /system;"
# end ramdisk changes

write_boot;

## end install
