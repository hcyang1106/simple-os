# note that script is executed under the image directory

if [ -f "disk1.vhd" ]; then
    mv disk1.vhd disk1.dmg
fi

if [ -f "disk2.vhd" ]; then
    mv disk2.vhd disk2.dmg
fi

# becomes env variable, current and child process can use it
export DISK1_NAME=disk1.dmg 

# boot, writes at the start of disk
# conv=notruc means not truncating disk1.dmg (output file) to the size of boot.bin (input file)
# uses bs size to read write
dd if=boot.bin of=$DISK1_NAME bs=512 conv=notrunc count=1

# loader also needs to be written to disk
# seek means jumps over how many blocks, since we want to write 2nd block, we put 1 here (index starts from 0)
dd if=loader.bin of=$DISK1_NAME bs=512 conv=notrunc seek=1

# write kernel, starting from sector 100
dd if=kernel.elf of=$DISK1_NAME bs=512 conv=notrunc seek=100

# temporary usage
# dd if=init.elf of=$DISK1_NAME bs=512 conv=notrunc seek=5000
# dd if=shell.elf of=$DISK1_NAME bs=512 conv=notrunc seek=5000

# write user programs to disk2 
# mount disk2
export DISK2_NAME=disk2.dmg
export TARGET_PATH=mp
rm $TARGET_PATH

# relative path, create if not exist
hdiutil attach $DISK2_NAME -mountpoint $TARGET_PATH 

# cp -v init.elf $TARGET_PATH/init
# # copy shell.elf to disk2
# cp -v shell.elf $TARGET_PATH 
# cp -v loop.elf $TARGET_PATH/loop
cp -v *.elf $TARGET_PATH

hdiutil detach $TARGET_PATH -verbose
