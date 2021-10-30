
max_blocks=10240000 #per comprendere anche system.img
#max_blocks=10240
names=""
compress=0

script=$(readlink -f "$0")
script_path=$(dirname "$script")
serial=$(cat /sys/class/android_usb/f_accessory/device/iSerial)

mount /system
sdk=$(grep "ro.build.version.sdk=" /system/build.prop | cut -d"=" -f2)
product=$(grep "ro.product.name=" /system/build.prop | cut -d"=" -f2)
builduser=$(grep "ro.build.version.incremental=" /system/build.prop | cut -d"=" -f2)
versionrelease=$(grep "ro.build.version.release=" /system/build.prop | cut -d"=" -f2)
serial_date=$product"_"$serial"_"$builduser"_"$(date +"%Y%m%d.%H%M.%S")"_"$versionrelease
output_path=$script_path/$serial_date
mkdir -p $output_path
mkdir -p $output_path/images
cat /system/build.prop >> $output_path/build.prop
if [[ "$sdk" -lt 23 ]]; then umount /system ; clear ; rm -rf $output_path ; echo "Sorry. System not supported!" ; echo " " ; return 1 ; fi
umount /system

part_dir=$(find /dev/block/platform -name by-name)
partitions=$(ls -la $part_dir | awk '{if ( $10 == "->")  print $9 ">" $11 }')

getprop > $output_path/default.prop

echo "<?xml version=\"1.0\" ?>" > $output_path/md5sum.xml
echo "<root>" >> $output_path/md5sum.xml
echo "  <digests>" >> $output_path/md5sum.xml
for f in $partitions
do
  part_id=$(echo $f | sed 's/^[^>]*>\/dev\/block\///')
  part_name=$(echo $f | sed 's/>.*//')
  size=$(cat /proc/partitions | awk -v p=$part_id '{if ( $4 == p ) print $3}')
  checksum="0"
 
  skip=0
  if [ $max_blocks -gt 0 -a $size -gt $max_blocks ]
  then
	skip=1
	echo "Skipping $part_name Id $part_id due to size"	
  else 
	if [ "$names" -ne "" ]
	then	
	   if echo $names | grep -w $part_name > /dev/null; then
	     skip=0
	   else
	     skip=1
		 echo "Skipping $part_name Id $part_id"	
	   fi
	fi
  fi 
 
  if [ "$skip" -eq "0" ]
  then
	echo "Processing $part_name Id $part_id Size $size";
	dd if=/dev/block/$part_id of=$output_path/$part_name.img	
	checksum=$(md5sum -b $output_path/$part_name.img | sed 's/ .*//')
  fi
  rm -rf $output_path/bk*.img
  if [ $checksum != 0 ] ; then
  	echo "    <digest hash=\"md5\" name=\"$part_name.img\">$checksum</digest>" >> $output_path/md5sum.xml
  fi
  echo "dd if=/tmp/images/$part_name.img of=/dev/block/$part_name" >> $output_path/restore0.sh
  echo "fastboot ICE1 flash $part_name ICE0/images/$part_name.img" >> $output_path/flash_all0.sh
  echo "fastboot %* flash $part_name %~dp0images\# $part_name.img" >> $output_path/flash_all0.bat
done
  echo "  </digests>" >> $output_path/md5sum.xml
  echo "</root>" >> $output_path/md5sum.xml
  find $output_path/md5sum.xml | grep -v 'bk' $output_path/md5sum.xml >> $output_path/md5sum1.xml ; rm -rf $output_path/md5sum.xml ; mv $output_path/md5sum1.xml $output_path/md5sum.xml
  find $output_path/flash_all0.sh | grep -v 'bk' $output_path/flash_all0.sh >> $output_path/flash_all00.sh
  find $output_path/flash_all0.bat | grep -v 'bk' $output_path/flash_all0.bat >> $output_path/flash_all00.bat
  find $output_path/flash_all00.sh | grep -v 'userdata' $output_path/flash_all00.sh >> $output_path/flash_all.sh
  find $output_path/flash_all00.bat | grep -v 'userdata' $output_path/flash_all00.bat >> $output_path/flash_all.bat
  echo "fastboot ICE1 reboot" >> $output_path/flash_all.sh
  echo "fastboot %* reboot" >> $output_path/flash_all.bat
  
  sed -i '1,1s/^/fastboot $* getvar serialno 2>\&1 | grep "^serialno: *ICE3"\n/g' $output_path/flash_all.sh
  sed -i '2,2s/^/if [ $? -ne 0 ] ; then echo "Missmatching image and device"; exit 1; fi\n/g' $output_path/flash_all.sh
  sed -i 's/ICE3/'$serial/g $output_path/flash_all.sh

  sed -i '1,1s/^/fastboot \%* getvar serialno 2>\&1 | findstr \/r \/c:"^serialno: *ICE3" || echo Missmatching image and device\n/g' $output_path/flash_all.bat
  sed -i '2,2s/^/fastboot \%* getvar serialno 2>\&1 | findstr \/r \/c:"^serialno: *ICE3" || exit \/B 1\n/g' $output_path/flash_all.bat
  sed -i 's/ICE3/'$serial/g $output_path/flash_all.bat
  
  sed -i 's/ICE1/$*/g' $output_path/flash_all.sh
  sed -i 's/ICE0/\`dirname $0`/g' $output_path/flash_all.sh
  sed -i 's/# //g' $output_path/flash_all.bat
  rm -rf $output_path/*0*
  mv $output_path/*.img $output_path/images
  chmod 775 $output_path/flash_all.*
  cd $script_path
  rm -rf backup_partitions.sh
  tar -cvzf $output_path.tgz *
  rm -rf $output_path
 
if [ "$compress" -eq "1" ]
then
	cd $script_path
	tar cz $serial_date > $output_path.tar.gz
	rm -rf $output_path
fi 