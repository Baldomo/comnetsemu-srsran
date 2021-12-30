# Variables
provider = ENV["CS_PROVIDER"] || "virtualbox"

CPUS = ENV["CS_CPUS"] || 4
RAM = ENV["CS_RAM"] || 8192

BOX = "bento/ubuntu-20.04"

BOX_LIBVIRT = "generic/ubuntu1804"

# Provisioning
$bootstrap= <<-SCRIPT
# Install dependencies
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

# Essential packages used by ./util/install.sh
apt-get install -y git make pkg-config sudo python3 libpython3-dev python3-dev python3-pip software-properties-common
# Test/Development utilities
apt-get install -y bash-completion htop dfc gdb tmux
apt-get install -y iperf iperf3
SCRIPT

$setup_x11_server= <<-SCRIPT
apt-get install -y xorg
apt-get install -y openbox
SCRIPT

$post_installation= <<-SCRIPT
# Install docker compose 2.x
mkdir -p /usr/local/lib/docker/cli-plugins
wget -q -O /usr/local/lib/docker/cli-plugins/docker-compose https://github.com/docker/compose/releases/download/v2.2.2/docker-compose-linux-x86_64
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Allow vagrant user to use Docker without sudo
usermod -aG docker vagrant
if [ -d /home/vagrant/.docker ]; then
    chown -R vagrant:vagrant /home/vagrant/.docker
fi
SCRIPT

Vagrant.configure("2") do |config|
    if Vagrant.has_plugin?("vagrant-vbguest")
        config.vbguest.auto_update = false
    end
    
    config.vm.define "comnetsemu-srsran" do |cs|
        cs.vm.provider "virtualbox" do |vb|
            vb.cpus = CPUS
            vb.memory = RAM
            # MARK: The CPU should enable SSE3 or SSE4 to compile DPDK applications.
            vb.customize ["setextradata", :id, "VBoxInternal/CPUM/SSE4.1", "1"]
            vb.customize ["setextradata", :id, "VBoxInternal/CPUM/SSE4.2", "1"]
        end
        
        cs.vm.provider "libvirt" do |libvirt|
            libvirt.driver = "kvm"
            libvirt.cpus = CPUS
            libvirt.memory = RAM
        end
        
        if provider == "virtualbox"
            cs.vm.box = BOX
            cs.vm.synced_folder ".", "/vagrant", disabled: true
            cs.vm.synced_folder "./comnetsemu", "/home/vagrant/comnetsemu", type: "virtualbox"
            cs.vm.synced_folder ".", "/home/vagrant/project", type: "virtualbox"
        elsif provider == "libvirt"
            cs.vm.box = BOX_LIBVIRT
            cs.vm.synced_folder ".", "/vagrant", disabled: true
            cs.vm.synced_folder "./comnetsemu", "/home/vagrant/comnetsemu", type: "rsync"
            cs.vm.synced_folder ".", "/home/vagrant/project", type: "rsync", 
                rsync__auto: true,
                rsync__exclude: ["comnetsemu", "comnetsemu-docs", "build/*.box", "env"]
        end
        
        
        cs.vm.hostname = "comnetsemu-srsran"
        cs.vm.box_check_update = true
        cs.vm.post_up_message = '
        VM already started! Run "$ vagrant ssh comnetsemu" to ssh into the runnung VM.
        
        **IMPORTANT!!!**: For all ComNetsEmu users and developers:
        
        **Please** run the upgrade process described [here](https://git.comnets.net/public-repo/comnetsemu#upgrade-comnetsemu-and-dependencies) when there is a new release
        published [here](https://git.comnets.net/public-repo/comnetsemu/-/tags).
        New features, fixes and other improvements require run the upgrade script **manually**.
        But the script will check and perform upgrade automatically and it does not take much time if you have a good network connection.
        '
        
        cs.vm.provision :shell, inline: $bootstrap, privileged: true
        cs.vm.provision :shell, inline: $setup_x11_server, privileged: true
        
        if provider == "virtualbox"
            # Workaround for vbguest plugin issue
            cs.vm.provision "shell", run: "always", inline: <<-WORKAROUND
            modprobe vboxsf || true
            WORKAROUND
        elsif provider == "libvirt"
            # Rsync is too outdated and breaks if version < 3.2 while uploading
            cs.vm.provision "shell", run: "always", inline: <<-RSYNC
            wget -P /tmp http://archive.ubuntu.com/ubuntu/pool/main/r/rsync/rsync_3.2.3-3ubuntu1_amd64.deb
            sudo apt install libxxhash0
            sudo dpkg -i /tmp/rsync_3.2.3-3ubuntu1_amd64.deb
            RSYNC
        end
        
        cs.vm.provision "shell", privileged: false, inline: <<-SHELL
        # Apply Xterm profile, looks nicer.
        cp /home/vagrant/comnetsemu/util/Xresources /home/vagrant/.Xresources
        # xrdb can not run directly during vagrant up. Auto-works after reboot.
        xrdb -merge /home/vagrant/.Xresources
        
        cd /home/vagrant/comnetsemu/util || exit
        PYTHON=python3 ./install.sh -a
        
        cd /home/vagrant/comnetsemu/ || exit
        # setup.py develop installs the package (typically just a source folder)
        # in a way that allows you to conveniently edit your code after it is
        # installed to the (virtual) environment, and have the changes take
        # effect immediately. Convinient for development
        sudo make develop
        
        # Build images for Docker hosts
        cd /home/vagrant/comnetsemu/test_containers || exit
        sudo bash ./build.sh
        
        # Run the customization shell script (for distribution $BOX) if it exits.
        cd /home/vagrant/comnetsemu/util || exit
        if [ -f "./vm_customize.sh" ]; then
        echo "*** Run VM customization script."
        bash ./vm_customize.sh
        fi
        SHELL
        
        cs.vm.provision :shell, inline: $post_installation, privileged: true
        
        # Always run this when use `vagrant up`
        # - Check to update all dependencies
        # ISSUE: The VM need to have Internet connection to boot up...
        #cs.vm.provision :shell, privileged: true, run: "always", inline: <<-SHELL
        #  cd /home/vagrant/comnetsemu/util || exit
        #  PYTHON=python3 ./install.sh -u
        #SHELL
        
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
        