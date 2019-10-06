#!/bin/sh -e -u

progname=sysinstall
fstab=uefi
ram_size="$(free | sed -n 's/^Mem: *\([0-9]*\).*/\1/p')"
swap_size="$(( ram_size * 5 / 4 ))"

usage()
{
printf '%s' "\
Usage: $progname
TODO
" >&2
}

while getopts 'cm:d:f:' OPT; do
	case "$OPT" in
	c) cacheopt=1 ;;
	m) mnt="$OPTARG" ;;
	d) disk="$OPTARG" ;;
	f) fstab="$OPTARG" ;;
	*) usage; exit 2 ;;
	esac
done
shift "$(( OPTIND - 1 ))"

if [ -z "${mnt-}" ]; then
	usage
	exit 2
fi

mkfs()
{
	dev="${1-}"
	type="${2-}"
	label="${3-}"

	if [ -n "$label" ]; then
		case "$type" in
		vfat) mkfs.vfat -n "$label" -- "$dev" ;;
		swap) mkswap -L "$label" -- "$dev" ;;
		ext4) mkfs.ext4 -L "$label" -- "$dev" ;;
		esac
	else
		case "$type" in
		vfat) mkfs.vfat -- "$dev" ;;
		swap) mkswap -- "$dev" ;;
		ext4) mkfs.ext4 -- "$dev" ;;
		esac
	fi
}

format()
{
	log 'Partitioning disk...'
	if [ -n "$gpt" ]; then
		log 'Creating GPT table...'
		# Create GPT partition table
		printf 'g\n'
		# Create partitions
		printf 'n\n\n\n+%s\n' "$@" | sed 's/+* .*//'
		# Save
		printf 'w\n'
	else
		# TODO is there some way to control primary vs extended partition?
		log 'Creating MBR table...'
		# Create MBR partition table and extended partition
		printf 'o\nn\ne\n\n\n\n'
		# Create partitions
		printf 'n\n\n+%s\n' "$@" | sed 's/+* .*//'
		# Save
		printf 'w\n'
	fi | fdisk -W always -- "$disk"

	# TODO mounting in separate function?
	log 'Formatting and mounting partitions...'
	fdisk -lo Device -- "$disk" | sed '1,/Device/d' |
	for partition in "$@"; do
		read -r dev
		printf '%s %s\n' "$dev" "${partition#* }"
	done |
	sort -k 4 |
	while IFS=' ' read -r dev type label dir; do
		mkfs "$dev" "$type" "$label"
		if [ -n "$dir" ]; then
			mkdir -p -- "$mnt/$dir"
			mount -- "$dev" "$mnt/$dir"
		fi
	done
}

install()
{
	log 'Clearing filesystem...'
	# TODO do not remove /boot/efi
	rm -rf -- "$mnt" || true

	log 'Mounting /dev, /proc, /sys...'
	mkdir -- "$mnt/dev" "$mnt/proc" "$mnt/sys"
	mount -B -- /dev "$mnt/dev"
	mount -B -- /proc "$mnt/proc"
	mount -B -- /sys "$mnt/sys"

	log 'Installing packages...'
	mkdir -p -- "$mnt/var/lib/pacman" "$mnt/var/log" "$mnt/var/cache/pacman/pkg"
	if [ -n "${cacheopt-}" ]; then
		pacman -r "$mnt" --hookdir "$mnt/etc/pacman.d/hooks" \
		       --cachedir "$mnt/var/cache/pacman/pkg" \
		       --noconfirm -Syyuu -- core-meta "$@"
	else
		pacman -r "$mnt" --hookdir "$mnt/etc/pacman.d/hooks" \
		       --noconfirm -Syyuu -- core-meta "$@"
	fi

	# TODO chroot in separate function
	log 'Installing GRUB...'
	if [ -d "$mnt/boot/efi" ]; then
		chroot -- "$mnt" grub-install --removable \
		                              --efi-directory=/boot/efi
	else
		# TODO get disk from lsblk -no PKNAME "$(df -P /boot | sed '1d; s/ .*//')"?
		chroot -- "$mnt" grub-install -- "$disk"
	fi
	chroot -- "$mnt" grub-mkconfig -o /boot/grub/grub.cfg

	log 'Configuring fstab...'
	chroot -- "$mnt" ln -sf "fstab.d/$fstab" /etc/fstab

	log 'Init pacman keyring...'
	chroot -- "$mnt" pacman-key --init
	chroot -- "$mnt" pacman-key --populate archlinux

	# TODO
	echo '...' > /mnt/etc/hostname
}

case "${disk:+$fstab}" in
bios)
	#       size        type  label    dir
	format "$swap_size  swap  SWAP" \
	       "512M        vfat  SYS-BOOT /boot" \
	       "20G         ext4  SYS      /" \
	       "20G         ext4  SYS-VAR  /var" \
	       "            ext4  SYS-HOME /home"
	;;
usb)
	# TODO
	format "512M        vfat  USB-BOOT /boot" \
	       "20G         ext4  USB      /" \
	       "20G         ext4  USB-VAR  /mnt/var" \
	       "            vfat  USB-DATA /mnt/data"
	;;
uefi)
	gpt=1
	format "512M        vfat  ESP      /boot/efi" \
	       "$swap_size  swap  SWAP" \
	       "512M        vfat  SYS-BOOT /boot" \
	       "20G         ext4  SYS      /" \
	       "20G         ext4  SYS-VAR  /var" \
	       "            ext4  SYS-HOME /home"
	;;
esac

install "$@"
