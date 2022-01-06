# Variables
provider = ENV["CS_PROVIDER"] || "virtualbox"

CPUS = ENV["CS_CPUS"] || 4
RAM = ENV["CS_RAM"] || 8192

BOX = "bento/ubuntu-20.04"
BOX_LIBVIRT = "generic/ubuntu1804"

# Provisioning
$bootstrap= <<-SCRIPT
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

APT_PKGS=(
  bash-completion
  dfc
  gdb
  git
  htop
  iperf
  iperf3
  make
  pkg-config
  python3
  python3-dev
  python3-pip
  sudo
  tmux
)
apt-get install -y --no-install-recommends "${APT_PKGS[@]}"

# Install docker compose 2.x
mkdir -p /usr/local/lib/docker/cli-plugins
wget -q -O /usr/local/lib/docker/cli-plugins/docker-compose https://github.com/docker/compose/releases/download/v2.2.2/docker-compose-linux-x86_64
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
SCRIPT

$setup_x11_server= <<-SCRIPT
apt-get install -y --no-install-recommends xorg openbox
SCRIPT

$setup_comnetsemu= <<-SCRIPT
# Apply Xterm profile, looks nicer.
cp /home/vagrant/comnetsemu/util/Xresources /home/vagrant/.Xresources
# xrdb can not run directly during vagrant up. Auto-works after reboot.
xrdb -merge /home/vagrant/.Xresources

cd /home/vagrant/comnetsemu/util || exit
PYTHON=python3 ./install.sh -a
# Install development tools
PYTHON=python3 ./install.sh -d

# Run the customization shell script (for distribution $BOX) if it exits.
cd /home/vagrant/comnetsemu/util || exit
if [ -f "./vm_customize.sh" ]; then
  echo "*** Run VM customization script."
  bash ./vm_customize.sh
fi
SCRIPT

$post_installation= <<-SCRIPT
# Allow vagrant user to use Docker without sudo
usermod -aG docker vagrant
if [ -d /home/vagrant/.docker ]; then
  chown -R vagrant:vagrant /home/vagrant/.docker
fi

apt-get autoclean -y
apt-get autoremove -y
SCRIPT

Vagrant.configure("2") do |config|
    if Vagrant.has_plugin?("vagrant-vbguest")
        config.vbguest.auto_update = false
    end
    
    config.vm.define "comnetsemu-srsran" do |cs|
        cs.vm.box = BOX

        cs.vm.provider "virtualbox" do |vb, override|
            vb.cpus = CPUS
            vb.memory = RAM
            # MARK: The vCPUs should have SSE4 to compile DPDK applications.
            vb.customize ["setextradata", :id, "VBoxInternal/CPUM/SSE4.1", "1"]
            vb.customize ["setextradata", :id, "VBoxInternal/CPUM/SSE4.2", "1"]

            override.vm.synced_folder ".", "/vagrant", disabled: true
            override.vm.synced_folder "./comnetsemu", "/home/vagrant/comnetsemu", type: "virtualbox"
            override.vm.synced_folder ".", "/home/vagrant/project", type: "virtualbox"
        end
    
        cs.vm.provider "libvirt" do |libvirt, override|
            # Overrides are used to modify default options that do not work for libvirt provider.
            override.vm.box = BOX_LIBVIRT
        
            libvirt.driver = "kvm"
            libvirt.cpus = CPUS
            libvirt.memory = RAM

            override.vm.synced_folder ".", "/vagrant", disabled: true
            override.vm.synced_folder "./comnetsemu", "/home/vagrant/comnetsemu", type: "rsync"
            override.vm.synced_folder ".", "/home/vagrant/project", type: "rsync", 
                rsync__auto: true,
                rsync__exclude: ["comnetsemu", "comnetsemu-docs", "build/*.box", "env"]

            # Rsync is too outdated and breaks if version < 3.2 while uploading
            override.vm.provision "shell", run: "always", inline: <<-RSYNC
            wget -P /tmp http://archive.ubuntu.com/ubuntu/pool/main/r/rsync/rsync_3.2.3-3ubuntu1_amd64.deb
            sudo apt install libxxhash0
            sudo dpkg -i /tmp/rsync_3.2.3-3ubuntu1_amd64.deb
            RSYNC
        end
        
        
        cs.vm.hostname = "comnetsemu-srsran"
        cs.vm.box_check_update = true
        cs.vm.post_up_message = '
        VM already started! Run "$ vagrant ssh comnetsemu-srsran" to ssh into the runnung VM.
        
        **IMPORTANT!!!**: For all ComNetsEmu users and developers:
        
        **Please** run the upgrade process described [here](https://git.comnets.net/public-repo/comnetsemu#upgrade-comnetsemu-and-dependencies) when there is a new release
        published [here](https://git.comnets.net/public-repo/comnetsemu/-/tags).
        New features, fixes and other improvements require run the upgrade script **manually**.
        But the script will check and perform upgrade automatically and it does not take much time if you have a good network connection.
        '
        
        cs.vm.provision :shell, inline: $bootstrap, privileged: true
        cs.vm.provision :shell, inline: $setup_x11_server, privileged: true
        cs.vm.provision :shell, inline: $setup_comnetsemu, privileged: false
        cs.vm.provision :shell, inline: $post_installation, privileged: true
        
        # VM networking
        cs.vm.network "forwarded_port", guest: 8888, host: 8888, host_ip: "127.0.0.1"
        cs.vm.network "forwarded_port", guest: 8082, host: 8082
        cs.vm.network "forwarded_port", guest: 8083, host: 8083
        cs.vm.network "forwarded_port", guest: 8084, host: 8084
        
        # Enable X11 forwarding
        cs.ssh.forward_agent = true
        cs.ssh.forward_x11 = true
    end
end
        