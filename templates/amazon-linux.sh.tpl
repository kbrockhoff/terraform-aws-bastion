#!/usr/bin/env bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

##
## Enable SSM
##
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent

%{ if mount_additional_volume ~}
##
## Mount additional data volume
##
echo "Mounting additional data volume..."

# Wait for the device to be available
DEVICE="${additional_volume_device}"
MOUNT_POINT="${additional_volume_mount}"

# Wait up to 60 seconds for device to be attached
for i in {1..60}; do
  if [ -e "$DEVICE" ]; then
    echo "Device $DEVICE found"
    break
  fi
  echo "Waiting for device $DEVICE to attach (attempt $i/60)..."
  sleep 1
done

if [ -e "$DEVICE" ]; then
  # Check if device has a filesystem, create if not
  if ! blkid "$DEVICE"; then
    echo "Creating filesystem on $DEVICE..."
    mkfs -t xfs "$DEVICE"
  fi
  
  # Create mount point if it doesn't exist
  if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating mount point $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"
  fi
  
  # Get the UUID of the device
  UUID=$(blkid -s UUID -o value "$DEVICE")
  
  # Add to fstab for persistent mounting
  if ! grep -q "$UUID" /etc/fstab; then
    echo "Adding device to /etc/fstab..."
    echo "UUID=$UUID $MOUNT_POINT xfs defaults,nofail 0 2" >> /etc/fstab
  fi
  
  # Mount the volume
  echo "Mounting $DEVICE to $MOUNT_POINT..."
  mount "$MOUNT_POINT"
  
  # Set permissions
  chmod 755 "$MOUNT_POINT"
  
  echo "Additional volume mounted successfully"
else
  echo "ERROR: Device $DEVICE not found after 60 seconds"
fi
%{ endif ~}

##
## Make root filesystem read-only (remount)
##
echo "Remounting root filesystem as read-only..."
mount -o remount,ro /
echo "Root filesystem is now read-only"

${user_data}
