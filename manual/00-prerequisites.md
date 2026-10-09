# 00 · Prerequisites

## Goal
Install the tools and set the host limits that two KinD clusters need.

## Hardware
You need 8 or more CPU cores, at least 16 GB RAM (32 GB is better) and about 30 GB of free disk.

## Steps

1. Install the tools. On Arch Linux:

   ```bash
   sudo pacman -S --needed docker docker-buildx kubectl helm jq openssl gettext curl
   yay -S kind-bin
   sudo systemctl enable --now docker
   sudo usermod -aG docker "$USER"
   ```

   Log out and back in so your user can run Docker without `sudo`. `gettext` provides `envsubst`, which fills the `${VARIABLE}` placeholders in the `.tmpl` files.

2. Raise the inotify limits. Without this, pods in the second cluster fail with "too many open files".

   ```bash
   echo -e 'fs.inotify.max_user_watches=524288\nfs.inotify.max_user_instances=512' | sudo tee /etc/sysctl.d/99-kind.conf
   sudo sysctl --system
   ```

3. Make sure ports 443, 80 and 8443 are free:

   ```bash
   ss -ltn | grep -E ':(443|80|8443)\s'
   ```

   If anything is printed, either stop that service or use other ports. Set them before you source `lab.env`:

   ```bash
   export HTTPS_PORT=9443 HTTP_PORT=9080
   ```

## Check
`docker run --rm hello-world` works without `sudo`, and `envsubst --version` prints a version.
